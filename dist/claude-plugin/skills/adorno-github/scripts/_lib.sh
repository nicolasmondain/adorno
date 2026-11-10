# shellcheck shell=bash
# shellcheck disable=SC2034  # REPO, OWNER, NAME, NUM and E_* are read by the scripts that source this file
# Shared helpers for adorno-github scripts. Sourced, never executed.
# Compatible with macOS bash 3.2: no associative arrays, no mapfile, no ${var,,}.

set -euo pipefail

ADORNO_GITHUB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(basename "$0")"
# Everything adorno keeps lives under ~/.adorno. No environment variable moves it: the registry and the runs decide what
# a script may write, so they are read from one place only (tests run with a throwaway HOME).
kit_home() { printf '%s' "$HOME/.adorno"; }
# The registry: the one `bin/kit install` writes outside every repo (~/.adorno/registry.json, read-only), else the
# public defaults shipped with this skill.
if [ -f "$(kit_home)/registry.json" ]; then
  REGISTRY="$(kit_home)/registry.json"
else
  REGISTRY="$ADORNO_GITHUB_DIR/../repos.json"
fi
# A registry older than your personal layer: an install was forgotten, a new repo or a tightened right is not known yet.
if [ "$REGISTRY" = "$(kit_home)/registry.json" ]; then
  _layer="$(jq -r '._layer.file // empty' "$REGISTRY" 2>/dev/null || true)"
  if [ -n "$_layer" ] && [ -f "$_layer" ] && [ "$_layer" -nt "$REGISTRY" ]; then
    printf '%s: %s changed since the last bin/kit install: these rights may be stale (run bin/kit install)\n' \
      "$(basename "$0")" "$_layer" >&2
  fi
fi

# Exit codes shared by every script (documented in SKILL.md).
E_USAGE=2 E_UNREGISTERED=3 E_POLICY=4 E_LEVEL=5

# A Conventional Commit header: the title of a PR, which a squash merge turns into the commit on the base branch.
CC_TITLE_RE='^(feat|fix|perf|refactor|test|docs|style|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: .+'

die()  { printf '%s: %s\n' "$SELF" "$1" >&2; exit "${2:-1}"; }
log()  { printf '%s: %s\n' "$SELF" "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

need gh
need jq
[ -f "$REGISTRY" ] || die "registry not found: $REGISTRY (run bin/kit install)"

# ── runs: what the current workflow was granted ───────────────────────────────────────────────────────────────────
# A workflow starts with `run-begin` (mode, level, denied actions, dry run, repos) and ends with `run-end`. The grant
# lives in a file, not in an environment variable (agents' shells do not keep them). A run applies only to the repos
# it names, and only in the session that opened it. No run applies to a repo → L0: every write is refused (fail
# closed). Several runs apply (one session, two workflows) → the strictest wins, and require_level says so.
runs_dir() { printf '%s/runs/active' "$(kit_home)"; }

# active_runs -> JSON array of the non-expired runs. An expired run file is removed; a file that does not parse is
# skipped (run-begin may be writing it) and removed only once it is an hour old.
active_runs() {
  local d f now out="[]"
  d="$(runs_dir)"; now="$(date +%s)"
  [ -d "$d" ] || { echo "[]"; return; }
  for f in "$d"/*.json; do
    [ -e "$f" ] || continue
    if ! jq -e 'type == "object" and (.expires | type) == "number"' "$f" >/dev/null 2>&1; then
      [ -z "$(find "$f" -mmin +60 2>/dev/null)" ] || rm -f "$f"
    elif jq -e --argjson now "$now" '.expires > $now' "$f" >/dev/null 2>&1; then
      out="$(jq --slurpfile r "$f" '. + $r' <<<"$out")"
    else
      rm -f "$f"
    fi
  done
  printf '%s\n' "$out"
}

# The session a run belongs to: Claude Code sets CLAUDE_CODE_SESSION_ID in every shell command it runs. In a session,
# only that session's runs count (another session's run can neither lower nor raise yours); without one (Codex,
# Gemini, a terminal), only the runs opened outside any session do.
session_id() { printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"; }

# grant [owner/repo] -> {level, deny, dry_run, runs, ids} for that repo: this session's active runs that name it,
# lowered (never raised) by ADORNO_LEVEL. Without a repo: those that name any repo (used for dry_run only).
grant() {
  active_runs | jq --arg env "${ADORNO_LEVEL:-}" --arg dry "${ADORNO_DRY_RUN:-0}" --arg repo "${1:-}" \
    --arg session "$(session_id)" '
    def n: {"L0":0,"L1":1,"L2":2,"L3":3,"L4":4}[.] // 0;
    [ .[] | select((.session // "") == $session) | select(((.repos // []) | length) > 0)
          | select($repo == "" or ((.repos | map(ascii_downcase) | index($repo | ascii_downcase)) != null)) ]
    | (if length == 0 then "L0" else (map(.level) | min_by(n)) end) as $runs
    | {level: (if $env != "" and ($env | n) < ($runs | n) then $env else $runs end),
       deny: ([.[].deny // [] | .[]] | unique),
       dry_run: ($dry == "1" or any(.[]; .dry_run == true)),
       runs: length, ids: map("\(.id) (\(.workflow), \(.mode))")}'
}

# dry_run — true when every write must only be printed (a report run applies, or ADORNO_DRY_RUN=1); uses $REPO when
# the script has parsed one
dry_run() { [ "$(grant "${REPO:-}" | jq -r .dry_run)" = "true" ]; }

# split_repo owner/repo -> sets OWNER NAME REPO
split_repo() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "expected owner/repo, got '${1:-}'" "$E_USAGE"
  REPO="$1"; OWNER="${1%%/*}"; NAME="${1##*/}"
}

# repo_of_url URL -> owner/repo of a GitHub remote URL (dies on anything else)
repo_of_url() {
  local url="${1%.git}"; url="${url%/}"
  case "$url" in
    git@github.com:*) printf '%s' "${url#git@github.com:}" ;;
    ssh://git@github.com/*|ssh://git@github.com:*/*) printf '%s' "${url#ssh://git@github.com*/}" ;;
    https://github.com/*|http://github.com/*|https://*@github.com/*) printf '%s' "${url#*github.com/}" ;;
    *) die "origin is not a GitHub remote ($url); pass owner/repo" "$E_USAGE" ;;
  esac
}

# current_repo -> owner/repo of the git repository in the current directory (its `origin` remote on GitHub)
current_repo() {
  local url
  url="$(git config --get remote.origin.url 2>/dev/null)" || die "not in a git repository with an origin remote; pass owner/repo" "$E_USAGE"
  repo_of_url "$url"
}

# push_repo DIR -> owner/repo that `git push origin` goes to: its pushurl when one is set, else its url (as written,
# before any insteadOf rewrite, like current_repo)
push_repo() {
  local url
  url="$(git -C "$1" config --get remote.origin.pushurl 2>/dev/null || git -C "$1" config --get remote.origin.url 2>/dev/null)" \
    || die "$1 has no origin remote" "$E_USAGE"
  repo_of_url "$url"
}

# parse_ref owner/repo#123 | owner/repo 123 -> sets OWNER NAME REPO NUM
parse_ref() {
  local ref="${1:-}" num="${2:-}"
  if [[ "$ref" == *#* ]]; then num="${ref##*#}"; ref="${ref%%#*}"; fi
  split_repo "$ref"
  [[ "$num" =~ ^[0-9]+$ ]] || die "expected a PR or issue number for $ref" "$E_USAGE"
  NUM="$num"
}

# repo_conf owner/repo -> the repo's resolved settings (resolve.jq: defaults, workspaces, presets, repo globs, exact
# entry); exit 3 if no scope of the registry declares it, 1 if the registry itself is broken.
repo_conf() {
  local out err
  err="$(work_dir)/resolve-err"
  out="$(jq --arg r "$1" -f "$ADORNO_GITHUB_DIR/resolve.jq" "$REGISTRY" 2>"$err")" \
    || die "cannot resolve $1: $(head -c 300 "$err")"
  [ -n "$out" ] || die "$1 is not declared in your local config (adorno.yaml: repos, workspaces) — add it before running workflows on it" "$E_UNREGISTERED"
  printf '%s\n' "$out"
}

# registered_map -> {"owner/repo": true|false} for the owner/repo names read on stdin (one per line)
registered_map() {
  local r out="{}" ok
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ok=false
    [ -z "$(jq --arg r "$r" -f "$ADORNO_GITHUB_DIR/resolve.jq" "$REGISTRY" 2>/dev/null)" ] || ok=true
    out="$(jq --arg r "$r" --argjson ok "$ok" '.[$r] = $ok' <<<"$out")"
  done
  printf '%s\n' "$out"
}

# Where dedicated clones and PR workspaces live (outside every working copy of the user).
workspace_dir() { printf '%s/workspaces/%s__%s/pr-%s' "$(kit_home)" "$OWNER" "$NAME" "$NUM"; }
cache_dir() { printf '%s/cache/%s__%s.git' "$(kit_home)" "$OWNER" "$NAME"; }
# Your own PR: the path of its branch worktree, written by pr-workspace and read by pr-push.
workspace_link() { printf '%s/workspaces/%s__%s/pr-%s.link' "$(kit_home)" "$OWNER" "$NAME" "$NUM"; }

# local_clone owner/repo -> the git common dir of the repository in the current directory when its origin is
# owner/repo (fetch URL and push URL); nothing otherwise
local_clone() {
  local url want
  url="$(git config --get remote.origin.url 2>/dev/null)" || return 0
  want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [ "$( (repo_of_url "$url") 2>/dev/null | tr '[:upper:]' '[:lower:]')" = "$want" ] || return 0
  [ "$( (push_repo .) 2>/dev/null | tr '[:upper:]' '[:lower:]')" = "$want" ] || return 0
  git rev-parse --path-format=absolute --git-common-dir
}

# branch_worktree GIT_DIR BRANCH -> the worktree where BRANCH is checked out, or nothing
branch_worktree() {
  git -C "$1" worktree list --porcelain \
    | awk -v b="branch refs/heads/$2" '/^worktree /{p=substr($0,10)} $0 == b {print p; exit}'
}

# exclude_agent_run DIR — run artefacts live in the workspace but are never part of the PR
exclude_agent_run() {
  local common
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
  mkdir -p "$common/info"
  grep -qx '.agent-run/' "$common/info/exclude" 2>/dev/null || echo '.agent-run/' >>"$common/info/exclude"
}

conf_get() { repo_conf "$1" | jq -r --arg k "$2" '.[$k] // empty | if type == "array" then join(",") else tostring end'; }

level_num() { case "$1" in L0) echo 0;; L1) echo 1;; L2) echo 2;; L3) echo 3;; L4) echo 4;; *) echo -1;; esac; }

# require_level owner/repo L3 [action] — every one of these must allow it: the repo's max_level, the level granted to
# the active run (run-begin; none → L0), the repo's `permissions.deny`, the run's denied actions, and the run's repos
# when it named some. Actions: push, reply, comment, resolve, rerequest, review, submit, open_pr, ci_rerun.
require_level() {
  local need_n max conf g granted
  need_n="$(level_num "$2")"
  conf="$(repo_conf "$1")"
  max="$(jq -r '.max_level // "L0"' <<<"$conf")"
  if [ "$(level_num "$max")" -lt "$need_n" ]; then
    die "$1 allows up to $max, this action needs $2" "$E_LEVEL"
  fi
  g="$(grant "$1")"
  granted="$(jq -r .level <<<"$g")"
  if [ "$(jq -r .runs <<<"$g")" -gt 1 ]; then
    log "several runs of this session cover $1, the strictest applies: $(jq -r '.ids | join("; ")' <<<"$g") (run-end the stale ones)"
  fi
  if [ "$(level_num "$granted")" -lt "$need_n" ]; then
    if [ "$(jq -r .runs <<<"$g")" = 0 ]; then
      die "no active run covers $1 for $2: start the workflow with run-begin (writes are refused outside a run)" "$E_LEVEL"
    fi
    die "this run was granted $granted, this action needs $2" "$E_LEVEL"
  fi
  if [ -n "${3:-}" ]; then
    if jq -e --arg a "$3" '(.permissions.deny // []) | index([$a])' >/dev/null <<<"$conf"; then
      die "$1 denies '$3' (permissions.deny in your local config)" "$E_POLICY"
    fi
    if jq -e --arg a "$3" '.deny | index([$a])' >/dev/null <<<"$g"; then
      die "the active run's mode does not allow '$3'" "$E_POLICY"
    fi
  fi
}

# with_lock NAME CMD… — runs CMD (in a subshell, with set -e: any failing step fails the whole command) while
# holding a lock shared by every adorno process on this machine (mkdir is atomic). The lock records its holder's
# pid: a lock whose holder is gone is taken over at once; one older than 10 minutes is stale. Waits up to 12 minutes.
with_lock() {
  local lock tries=0 name="$1" pid rc=0; shift
  lock="$(kit_home)/locks/$name.lock"
  mkdir -p "$(kit_home)/locks"
  until mkdir "$lock" 2>/dev/null; do
    pid="$(cat "$lock/pid" 2>/dev/null || true)"
    if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
      rm -rf "$lock"; continue
    fi
    tries=$((tries + 1))
    [ "$tries" -lt 3600 ] || die "timed out waiting for lock $name" 6
    sleep 0.2
  done
  echo "$$" >"$lock/pid"
  trap 'rm -rf "$lock"' EXIT INT TERM
  # not `( … ) || rc=$?`: set -e is ignored in the left side of || (and in callers' conditions, so the commands
  # given to with_lock also check their own steps)
  set +e; ( set -e; "$@" ); rc=$?; set -e
  rm -rf "$lock"; trap - EXIT INT TERM
  return "$rc"
}

viewer_login() { gh api user --jq .login; }

# require_own_open_pr owner/repo N [field,…] — dies unless PR N is yours, from this repository (not a fork) and open;
# prints its JSON (author, isCrossRepository, state and the extra fields). The one rule pr-edit, pr-ready and
# run-check --pr (what the guard trusts) share.
require_own_open_pr() {
  local info
  info="$(gh pr view "$2" -R "$1" --json "author,isCrossRepository,state${3:+,$3}")"
  [ "$(jq -r .author.login <<<"$info")" = "$(viewer_login)" ] || die "$1#$2 is not your PR" "$E_POLICY"
  [ "$(jq -r .isCrossRepository <<<"$info")" = "false" ] || die "$1#$2 comes from a fork" "$E_POLICY"
  [ "$(jq -r .state <<<"$info")" = "OPEN" ] || die "$1#$2 is not open" "$E_POLICY"
  printf '%s\n' "$info"
}

# require_cc_title "title" — dies unless it is a Conventional Commit header (pr-open, pr-edit)
require_cc_title() {
  [[ "$1" =~ $CC_TITLE_RE ]] || die "title is not a Conventional Commit header: $1" "$E_USAGE"
}

# require_work_branch owner/repo BRANCH — dies on the base or a shared branch: nothing is committed nor pushed there
# by an agent (git-push, run-check --work-branch)
require_work_branch() {
  local base
  base="$(conf_get "$1" base)"
  [ -n "$base" ] || base="$(gh repo view "$1" --json defaultBranchRef --jq .defaultBranchRef.name)"
  case "$2" in
    ""|"$base"|main|master|develop|production|staging) die "refusing ${2:-a detached HEAD}: a base or shared branch" "$E_POLICY" ;;
  esac
}

# thread_of owner/repo N THREAD_ID — dies unless the review thread belongs to that PR (a thread id is global: without
# this, a write gated on repo A could land on a thread of repo B)
thread_of() {
  local got
  [[ "$3" =~ ^[A-Za-z0-9_=-]+$ ]] || die "invalid thread id '$3'" "$E_USAGE"
  got="$(gh api graphql -f query='query($id:ID!){ node(id:$id){ ... on PullRequestReviewThread {
      pullRequest { number repository { nameWithOwner } } } } }' -F id="$3" \
    --jq '.data.node.pullRequest | "\(.repository.nameWithOwner)#\(.number)"' 2>/dev/null || true)"
  [ "$(printf '%s' "$got" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s#%s' "$1" "$2" | tr '[:upper:]' '[:lower:]')" ] \
    || die "thread $3 does not belong to $1#$2 (it is on ${got:-an unknown PR})" "$E_POLICY"
}

# with_footer owner/repo FILE -> path of FILE, or of a copy with the repo's `reply_footer` appended
with_footer() {
  local footer out
  footer="$(conf_get "$1" reply_footer)"
  if [ -z "$footer" ]; then printf '%s' "$2"; return; fi
  out="$(work_dir)/footer-$$-$RANDOM.md"
  { cat "$2"; printf '\n\n%s\n' "$footer"; } >"$out"
  printf '%s' "$out"
}

# workspace_clean_state DIR REF -> dies if DIR has uncommitted changes or commits not in REF
workspace_clean_state() {
  local ahead
  [ -z "$(git -C "$1" status --porcelain)" ] || die "workspace $1 has uncommitted changes" "$E_POLICY"
  ahead="$(git -C "$1" rev-list --count "$2..HEAD")"
  [ "$ahead" = "0" ] || die "workspace $1 has $ahead commit(s) not pushed; run pr-push first" "$E_POLICY"
}

# work_dir -> a scratch folder private to this process (parallel runs never share files) and to you (mode 700):
# ~/.adorno/tmp/<pid>. It holds diffs, CI logs and payloads that the agent reads after the script exits, so it is not
# removed on exit; folders older than a day are.
work_dir() {
  local base d
  base="$(kit_home)/tmp"; d="$base/$$"
  if [ ! -d "$d" ]; then
    (umask 077; mkdir -p "$d")
    find "$base" -mindepth 1 -maxdepth 1 -type d -mtime +0 -exec rm -rf {} + 2>/dev/null || true
  fi
  printf '%s' "$d"
}
