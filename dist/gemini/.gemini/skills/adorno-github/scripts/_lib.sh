# shellcheck shell=bash
# shellcheck disable=SC2034  # REPO, OWNER, NAME, NUM and E_* are read by the scripts that source this file
# Shared helpers for adorno-github scripts. Sourced, never executed.
# Compatible with macOS bash 3.2: no associative arrays, no mapfile, no ${var,,}.

set -euo pipefail

GH_OPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${ADORNO_REPOS:-$GH_OPS_DIR/../repos.json}"
SELF="$(basename "$0")"

# Exit codes shared by every script (documented in SKILL.md).
E_USAGE=2 E_UNREGISTERED=3 E_POLICY=4 E_LEVEL=5

die()  { printf '%s: %s\n' "$SELF" "$1" >&2; exit "${2:-1}"; }
log()  { printf '%s: %s\n' "$SELF" "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

need gh
need jq
[ -f "$REGISTRY" ] || die "registry not found: $REGISTRY (set ADORNO_REPOS)"

dry_run() { [ "${GH_OPS_DRY_RUN:-0}" = "1" ]; }

# split_repo owner/repo -> sets OWNER NAME REPO
split_repo() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "expected owner/repo, got '${1:-}'" "$E_USAGE"
  REPO="$1"; OWNER="${1%%/*}"; NAME="${1##*/}"
}

# current_repo -> owner/repo of the git repository in the current directory (its `origin` remote on GitHub)
current_repo() {
  local url
  url="$(git remote get-url origin 2>/dev/null)" || die "not in a git repository with an origin remote; pass owner/repo" "$E_USAGE"
  url="${url%.git}"; url="${url%/}"
  case "$url" in
    git@github.com:*) printf '%s' "${url#git@github.com:}" ;;
    ssh://git@github.com/*) printf '%s' "${url#ssh://git@github.com/}" ;;
    https://github.com/*|http://github.com/*) printf '%s' "${url#*github.com/}" ;;
    *) die "origin is not a GitHub remote ($url); pass owner/repo" "$E_USAGE" ;;
  esac
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
# entry); exit 3 if no scope of the registry declares it.
repo_conf() {
  local out
  out="$(jq --arg r "$1" -f "$GH_OPS_DIR/resolve.jq" "$REGISTRY" 2>/dev/null)" || out=""
  [ -n "$out" ] || die "$1 is not declared in your local config (adorno.yaml: repos, workspaces) — add it before running workflows on it" "$E_UNREGISTERED"
  printf '%s\n' "$out"
}

# Where dedicated clones and PR workspaces live (outside every working copy of the user).
kit_home() { printf '%s' "${ADORNO_HOME:-$HOME/.adorno}"; }
workspace_dir() { printf '%s/workspaces/%s__%s/pr-%s' "$(kit_home)" "$OWNER" "$NAME" "$NUM"; }
cache_dir() { printf '%s/cache/%s__%s.git' "$(kit_home)" "$OWNER" "$NAME"; }

conf_get() { repo_conf "$1" | jq -r --arg k "$2" '.[$k] // empty | if type == "array" then join(",") else tostring end'; }

level_num() { case "$1" in L0) echo 0;; L1) echo 1;; L2) echo 2;; L3) echo 3;; L4) echo 4;; *) echo -1;; esac; }

# require_level owner/repo L3 [action] — the repo's max_level AND the run's granted level must allow it, and the
# repo's `permissions.deny` must not list the action (push, reply, comment, resolve, rerequest, review, submit,
# open_pr, ci_rerun).
require_level() {
  local need_n max granted conf
  need_n="$(level_num "$2")"
  conf="$(repo_conf "$1")"
  max="$(jq -r '.max_level // "L0"' <<<"$conf")"
  if [ "$(level_num "$max")" -lt "$need_n" ]; then
    die "$1 allows up to $max, this action needs $2" "$E_LEVEL"
  fi
  granted="${ADORNO_LEVEL:-}"
  if [ -n "$granted" ] && [ "$(level_num "$granted")" -lt "$need_n" ]; then
    die "this run was granted $granted, this action needs $2" "$E_LEVEL"
  fi
  if [ -n "${3:-}" ] && jq -e --arg a "$3" '(.permissions.deny // []) | index([$a])' >/dev/null <<<"$conf"; then
    die "$1 denies '$3' (permissions.deny in your local config)" "$E_POLICY"
  fi
}

viewer_login() { gh api user --jq .login; }

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

work_dir() {
  local d="${AGENT_RUN_DIR:-${TMPDIR:-/tmp}/adorno-github}"
  mkdir -p "$d" && printf '%s' "$d"
}
