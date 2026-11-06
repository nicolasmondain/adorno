#!/usr/bin/env bash
# Tests for src/skills/adorno-github/scripts against a fake `gh`. No network.
# Usage: tests/adorno-github.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/src/skills/adorno-github/scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"; ln -s "$ROOT/tests/fake-gh" "$TMP/bin/gh"
# a throwaway home: the scripts read the registry and the runs from ~/.adorno only
export HOME="$TMP/home" PATH="$TMP/bin:$PATH"
KH="$HOME/.adorno"; mkdir -p "$KH"
reg() { rm -f "$KH/registry.json"; cp "$1" "$KH/registry.json"; chmod 400 "$KH/registry.json"; }  # reg FILE: use FILE as the registry
reg "$ROOT/tests/fixtures/repos.json"
git config --global user.email t@t; git config --global user.name t
export FAKE_FIX="$ROOT/tests/fixtures" FAKE_LOG="$TMP/gh.log" ADORNO_POLL=0
unset ADORNO_LEVEL ADORNO_DRY_RUN

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko()   { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
# expect_exit CODE NAME -- cmd...
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err")"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(cat "$TMP/err")"; fi
}
expect_jq() {  # expect_jq NAME FILTER (evaluated on $out, must be true)
  if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $out"; fi
}

echo "runs: no run, no write"
printf 'Thanks\n' >"$TMP/norun.md"
expect_exit 5 "no active run: a write is refused (fail closed)" -- "$S/pr-reply" acme/docs#42 T1 "$TMP/norun.md"
grep -q "run-begin" "$TMP/err" && ok "the refusal says how to start a run" || ko "the refusal says how to start a run"
ADORNO_LEVEL=L3 expect_exit 5 "ADORNO_LEVEL alone cannot grant a write" -- "$S/pr-reply" acme/docs#42 T1 "$TMP/norun.md"
expect_exit 5 "L4 is never granted" -- "$S/run-begin" --workflow workflow:x:y --mode auto --level L4
expect_exit 2 "a run names its repos" -- "$S/run-begin" --workflow workflow:x:y --mode auto --level L3
expect_exit 2 "an unknown mode is refused (no silent L3 for a typo)" -- "$S/run-begin" --workflow workflow:x:y --mode drafty --level L3 --repo acme/docs
expect_exit 0 "draft run" -- "$S/run-begin" --workflow workflow:review:received --mode draft --level L3 --repo acme/docs
expect_jq "draft: push denied, dry run, run folder" '.deny == ["push"] and .dry_run == true and (.dir | test("/runs/review-received-"))'
DRAFT="$(jq -r .id <<<"$out")"
expect_exit 0 "a reply in a draft run is only printed (dry run from the run file)" -- \
  sh -c "ADORNO_LEVEL= \"$S/pr-reply\" acme/docs#42 T1 \"$TMP/norun.md\""
expect_jq "dry run" '.dryRun == true'
expect_exit 0 "end the draft run" -- "$S/run-end" "$DRAFT"
expect_exit 2 "ending twice is an error" -- "$S/run-end" "$DRAFT"
expect_exit 0 "report run" -- "$S/run-begin" --workflow workflow:pr:review --mode report --level L3 --repo acme/docs
expect_jq "report: forced to L0" '.level == "L0" and .dry_run == true'
REPORT="$(jq -r .id <<<"$out")"
expect_exit 0 "an auto run on the same repo" -- "$S/run-begin" --workflow workflow:pr:review --mode auto --level L3 --repo acme/docs
AUTO="$(jq -r .id <<<"$out")"
expect_exit 5 "the strictest active run wins (report L0 alongside auto L3)" -- "$S/pr-comment" acme/docs#42 "$TMP/norun.md"
grep -q "several runs cover acme/docs" "$TMP/err" && ok "... and the script names the runs" || ko "... and the script names the runs" "$(cat "$TMP/err")"
"$S/run-end" "$REPORT" >/dev/null; "$S/run-end" "$AUTO" >/dev/null
expect_exit 0 "a run scoped to one repo" -- "$S/run-begin" --workflow workflow:pr:review --mode auto --level L3 --repo acme/strict
SCOPED="$(jq -r .id <<<"$out")"
expect_exit 5 "a run scoped to another repo does not apply here" -- "$S/pr-comment" acme/docs#42 "$TMP/norun.md"
expect_exit 0 "a draft run on another repo" -- "$S/run-begin" --workflow workflow:review:received --mode draft --level L3 --repo acme/docs
OTHER="$(jq -r .id <<<"$out")"
DRY_OUT="$("$S/pr-comment" acme/strict#7 "$TMP/norun.md" 2>/dev/null </dev/null)"
case "$DRY_OUT" in *dryRun*) ko "a draft run on another repo leaves this one alone" "$DRY_OUT" ;; *) ok "a draft run on another repo leaves this one alone" ;; esac
"$S/run-end" "$SCOPED" >/dev/null; "$S/run-end" "$OTHER" >/dev/null
printf '{ half' >"$KH/runs/active/20990101T000000-1-1.json"
expect_exit 5 "a half-written run file is ignored..." -- "$S/pr-comment" acme/docs#42 "$TMP/norun.md"
[ -f "$KH/runs/active/20990101T000000-1-1.json" ] && ok "... and not deleted while it may be in progress" || ko "... and not deleted"
rm -f "$KH/runs/active/20990101T000000-1-1.json"
# the rest of the suite runs inside one auto run at L3
"$S/run-begin" --workflow workflow:test:suite --mode auto --level L3 \
  --repo acme/docs --repo acme/strict --repo acme/app --repo acme/docs-public --repo acme/readonly --repo other/thing >/dev/null

echo "registry and usage"
expect_exit 3 "unregistered repo is refused" -- "$S/pr-feedback-fetch" foo/bar#1
expect_exit 2 "missing PR number is a usage error" -- "$S/pr-feedback-fetch" acme/docs
expect_exit 0 "repo-conf merges defaults" -- "$S/repo-conf" acme/strict
expect_jq "repo-conf: repo value wins, base filled from GitHub" \
  '.resolve_threads == "reviewer" and .reply_language == "en" and .base == "main"'

for url in git@github.com:acme/strict.git https://github.com/acme/strict ssh://git@github.com/acme/strict.git \
    https://someone@github.com/acme/strict.git ssh://git@github.com:22/acme/strict.git; do
  d="$TMP/cur-$RANDOM"; git init -q "$d"; git -C "$d" remote add origin "$url"
  out="$(cd "$d" && "$S/repo-conf" 2>"$TMP/err")"; got=$?
  if [ "$got" = 0 ] && jq -e '.repo == "acme/strict"' >/dev/null <<<"$out"; then ok "current repo from $url"; else ko "current repo from $url" "exit $got: $(cat "$TMP/err")"; fi
done
d="$TMP/cur-none"; mkdir -p "$d"
(cd "$d" && "$S/repo-conf" >/dev/null 2>&1); [ $? = 2 ] && ok "no git repo: usage error" || ko "no git repo: usage error"

echo "resolution: presets, workspaces, globs, permissions"
expect_exit 0 "workspace glob registers a repo absent from repos" -- "$S/repo-conf" acme/anything
expect_jq "workspace layer: preset expanded (nested use), context added" \
  '.team.name == "x" and .reviewers == ["carol"] and .context == ["preset line", "workspace line"] and .scopes == ["defaults", "workspace:acme-all"]'
expect_exit 0 "exact entry over glob over workspace" -- "$S/repo-conf" acme/docs-public
expect_jq "context and vision accumulate, scopes in order" \
  '.context == ["preset line", "workspace line", "exact line"] and .vision == ["docs glob vision"] and .scopes == ["defaults", "workspace:acme-all", "repos:acme/docs-*", "repos:acme/docs-public"]'
expect_exit 0 "exact entry keeps its own reviewers over the workspace's" -- "$S/repo-conf" acme/docs
expect_jq "acme/docs reviewers" '.reviewers == ["alice", "octocat"]'
expect_exit 0 "a glob alone registers a repo" -- "$S/repo-conf" other/thing
expect_jq "glob settings apply" '.max_level == "L1" and .scopes == ["defaults", "repos:other/*"]'
expect_exit 3 "no scope declares it: unregistered" -- "$S/repo-conf" nobody/repo
printf 'Thanks\n' >"$TMP/pbody.md"
expect_exit 4 "permissions.deny blocks a reply" -- "$S/pr-reply" acme/docs-public#1 T1 "$TMP/pbody.md"
expect_exit 5 "glob max_level L1 blocks a reply" -- "$S/pr-reply" other/thing#1 T1 "$TMP/pbody.md"
printf '{"body":"ok","comments":[]}' >"$TMP/pending.json"
printf '{"event":"COMMENT","body":"ok","comments":[]}' >"$TMP/submit.json"
FAKE_REVIEWS="$FAKE_FIX/reviews.json" expect_exit 0 "deny submit still allows a pending review" -- "$S/pr-review-submit" acme/docs-public#1 "$TMP/pending.json"
expect_exit 4 "deny submit blocks a submitted review" -- "$S/pr-review-submit" acme/docs-public#1 "$TMP/submit.json"

echo "pr-feedback-fetch"
expect_exit 0 "fetches" -- "$S/pr-feedback-fetch" acme/docs#42
expect_jq "only unresolved threads" '[.threads[].id] == ["T1","T2"]'
expect_jq "needsReply false when I spoke last" '(.threads[] | select(.id=="T2") | .needsReply) == false'
expect_jq "needsReply true when the reviewer spoke last" '(.threads[] | select(.id=="T1") | .needsReply) == true'
expect_jq "my own reviews are dropped" '[.reviews[].author] == ["alice","carol"]'
expect_jq "ghost authors are named, mine dropped" '[.conversation[].author] == ["bob","ghost","ci-bot"]'
expect_jq "comment before my last reply needs none" '(.conversation[] | select(.author=="bob") | .needsReply) == false'
expect_jq "comment after my last reply needs one" '(.conversation[] | select(.author=="ghost") | .needsReply) == true'
expect_jq "bots never need a reply" '(.conversation[] | select(.author=="ci-bot") | .bot and (.needsReply | not))'
expect_jq "review summary after my reply needs one" '[.reviews[] | select(.needsReply) | .author] == ["carol"]'
expect_jq "needsReplyCount sums threads, comments, reviews" '.needsReplyCount == 3'
expect_jq "CI state and ownership surfaced" '.pr.ci == "FAILURE" and .pr.head == "nm/pagination" and .pr.mine'

echo "pr-status"
expect_exit 0 "lists PRs" -- "$S/pr-status"
expect_jq "blocker: unresolved threads before review" '(.[] | select(.number==42) | .blocker) == "changes-requested"'
expect_jq "blocker: red CI first" '(.[] | select(.number==7) | .blocker) == "ci-red"'
expect_jq "team and user reviewers listed" '(.[] | select(.number==7) | .waitingOn) == ["carol","core-team"]'
expect_jq "unregistered repos flagged" '(.[] | select(.repo=="someone/else") | .registered) == false'

echo "writes: levels, dry run, policy"
printf 'Fixed in abc123.\n' >"$TMP/body.md"
expect_exit 5 "repo max_level L0 blocks a reply" -- "$S/pr-reply" acme/readonly#1 T1 "$TMP/body.md"
ADORNO_LEVEL=L2 expect_exit 5 "run granted L2 cannot reply (L3)" -- "$S/pr-reply" acme/docs#42 T1 "$TMP/body.md"
ADORNO_DRY_RUN=1 expect_exit 0 "dry-run reply" -- "$S/pr-reply" acme/docs#42 T1 "$TMP/body.md"
expect_jq "dry-run shows the body, posts nothing" '.dryRun and .body == "Fixed in abc123.\n"'
grep -q addPullRequestReviewThreadReply "$FAKE_LOG" && ko "dry-run must not call the mutation" || ok "dry-run did not call the mutation"
expect_exit 0 "real reply" -- "$S/pr-reply" acme/docs#42 T1 "$TMP/body.md"
expect_jq "reply returns the comment url" '.posted and (.url | test("#r1$"))'
printf '' >"$TMP/empty.md"
expect_exit 2 "empty body refused" -- "$S/pr-reply" acme/docs#42 T1 "$TMP/empty.md"

expect_exit 4 "resolve refused when the reviewer resolves" -- "$S/pr-resolve" acme/strict#7 T1
FAKE_PR_AUTHOR=alice expect_exit 4 "resolve refused on someone else's PR" -- "$S/pr-resolve" acme/docs#42 T1
expect_exit 0 "resolve as author" -- "$S/pr-resolve" acme/docs#42 T1
expect_jq "thread resolved" '.resolved == true'

ADORNO_DRY_RUN=1 expect_exit 0 "rerequest defaults to past human reviewers" -- "$S/pr-rerequest" acme/docs#42
expect_jq "bots and myself excluded, deduplicated" '.reviewers == ["alice","bob"]'
expect_exit 0 "rerequest named reviewer" -- "$S/pr-rerequest" acme/docs#42 carol
expect_jq "requested carol" '.requested == ["carol"]'

FAKE_THREAD_REPO=acme/strict expect_exit 4 "a thread of another repo is refused" -- "$S/pr-reply" acme/docs#42 T1 "$TMP/body.md"
FAKE_THREAD_NUM=7 expect_exit 4 "a thread of another PR is refused" -- "$S/pr-resolve" acme/docs#42 T1
expect_exit 2 "a malformed thread id is refused" -- "$S/pr-reply" acme/docs#42 'T1;x' "$TMP/body.md"
echo "pr-open"
expect_exit 2 "non-conventional title refused" -- "$S/pr-open" acme/docs feat/lem-1-x "Add stuff" "$TMP/body.md"
expect_exit 4 "branch outside branch_pattern refused" -- "$S/pr-open" acme/docs nm/lem-1-x "feat: add stuff" "$TMP/body.md"
ADORNO_DRY_RUN=1 expect_exit 0 "dry-run open" -- "$S/pr-open" acme/docs feat/lem-123-pagination "feat(api)!: add stuff" "$TMP/body.md" --draft
expect_jq "targets the base, as draft" '.base == "main" and .draft and .head == "feat/lem-123-pagination"'
expect_jq "the author is never requested as reviewer" '.reviewers == ["alice"]'
expect_exit 0 "open" -- "$S/pr-open" acme/docs fix/lem-9-x "fix: add stuff" "$TMP/body.md"
expect_jq "returns the url" '.opened and (.url | test("/pull/99$"))'

echo "ci"
FAKE_CHECKS="$ROOT/tests/fixtures/checks-pass.json" expect_exit 0 "green checks pass" -- "$S/ci-wait" acme/docs#42 0
expect_jq "state pass" '.state == "pass"'
FAKE_CHECKS="$ROOT/tests/fixtures/checks-fail.json" FAKE_CHECKS_EXIT=1 expect_exit 1 "a failing check fails at once" -- "$S/ci-wait" acme/docs#42 0
FAKE_CHECKS="$ROOT/tests/fixtures/checks-required-pass.json" FAKE_CHECKS_EXIT=8 expect_exit 0 "only required checks are awaited" -- "$S/ci-wait" acme/strict#7 0
FAKE_CHECKS="$ROOT/tests/fixtures/checks-required-pass.json" FAKE_CHECKS_EXIT=8 expect_exit 6 "pending past timeout" -- "$S/ci-wait" acme/docs#42 0
FAKE_ATTEMPT=2 expect_exit 4 "no second rerun of the same run" -- "$S/ci-rerun" acme/docs 123
ADORNO_DRY_RUN=1 expect_exit 0 "first rerun allowed" -- "$S/ci-rerun" acme/docs 123

echo "pr-review-requested"
expect_exit 0 "lists review requests" -- "$S/pr-review-requested"
expect_jq "direct request detected" '(.[] | select(.number==10) | .direct) == true'
expect_jq "team request kept, not direct" '(.[] | select(.number==11) | (.direct | not) and .viaTeams == ["backend"])'
expect_jq "already reviewed head flagged and sorted last" '.[-1].number == 11 and .[-1].reviewedHead'
expect_jq "unregistered repo flagged" '(.[] | select(.number==12) | .registered) == false'
expect_jq "my pending review is surfaced" '(.[] | select(.number==10) | .pendingReview) and ((.[] | select(.number==11) | .pendingReview) | not)'

echo "pr-areas (public default rules from repos.yaml)"
REAL="$ROOT/dist/claude/.claude/skills/adorno-github/repos.json"
if [ -f "$REAL" ]; then
  jq '.repos = {"acme/app": {}, "acme/docs": {"area_reviewers": {"docs": ["agent:review:security"]}}}' "$REAL" >"$TMP/areas-repos.json"
  reg "$TMP/areas-repos.json"
  expect_exit 0 "classifies a diff" -- "$S/pr-areas" acme/app "$ROOT/tests/fixtures/sample.diff"
  expect_jq "front by extension" '.areas.front == ["client/app.tsx"]'
  expect_jq "mongodb by added-line content" '.areas.mongodb == ["server/users.js"] and .areas.back == ["server/users.js"]'
  expect_jq "deps and docs" '.areas.deps == ["package.json"] and .areas.docs == ["README.md"]'
  expect_jq "unmatched files land in other" '.other == ["notes/weird.txt"]'
  expect_jq "reviewers: always + per area, deduplicated" \
    '(.reviewers | sort) == (["agent:review:code","agent:review:ponytail","agent:review:front","agent:review:perf","agent:review:back","agent:review:tests","agent:review:mongodb","agent:review:security"] | sort)'
  expect_exit 0 "per-repo override" -- "$S/pr-areas" acme/docs "$ROOT/tests/fixtures/sample.diff"
  expect_jq "override merges with default areas" '.areas.front == ["client/app.tsx"] and (.reviewers | index("agent:review:security"))'
  jq -e '.repos == {}' "$REAL" >/dev/null && ok "public registry has no repos" || ko "public registry has no repos"
  reg "$ROOT/tests/fixtures/repos.json"
else
  ko "pr-areas tests need dist/ — run bin/kit build first"
fi

echo "pr-review-submit"
printf '%s' '{"event":"COMMENT","body":"Looks good overall.","comments":[{"path":"a.ts","line":3,"body":"Null check?"}]}' >"$TMP/review.json"
FAKE_PR_AUTHOR=alice ADORNO_DRY_RUN=1 expect_exit 0 "dry-run review" -- "$S/pr-review-submit" acme/docs#10 "$TMP/review.json"
expect_jq "payload pinned to the head commit, side defaulted" '.commit_id == "abc123" and .comments[0].side == "RIGHT"'
jq '.event = "APPROVE"' "$TMP/review.json" >"$TMP/approve.json"
FAKE_PR_AUTHOR=alice expect_exit 4 "automatic approval refused by default" -- "$S/pr-review-submit" acme/docs#10 "$TMP/approve.json"
jq '.event = "REQUEST_CHANGES"' "$TMP/review.json" >"$TMP/rc.json"
expect_exit 4 "request changes on my own PR refused" -- "$S/pr-review-submit" acme/docs#42 "$TMP/rc.json"
FAKE_PR_AUTHOR=alice expect_exit 0 "request changes on a colleague's PR" -- "$S/pr-review-submit" acme/docs#10 "$TMP/rc.json"
expect_jq "posted inline" '.submitted and .inline == 1 and (.folded | not)'
FAKE_LAST_REVIEW="$TMP/last.json" FAKE_REVIEW_422=1 FAKE_PR_AUTHOR=alice expect_exit 0 "inline rejected: folded into body" -- "$S/pr-review-submit" acme/docs#10 "$TMP/review.json"
expect_jq "fold reported" '.folded and .inline == 0'
jq -e '(.comments | length) == 0 and (.body | test("a.ts:3"))' "$TMP/last.json" >/dev/null && ok "folded body carries the comment" || ko "folded body carries the comment"
printf '{"event":"LGTM","body":""}' >"$TMP/bad.json"
expect_exit 2 "invalid review refused" -- "$S/pr-review-submit" acme/docs#10 "$TMP/bad.json"

printf '%s' '{"body":"","comments":[{"path":"a.ts","line":3,"body":"issue (blocking): null check?"}]}' >"$TMP/pending.json"
FAKE_PR_AUTHOR=alice ADORNO_DRY_RUN=1 expect_exit 0 "no event means a pending review" -- "$S/pr-review-submit" acme/docs#10 "$TMP/pending.json"
expect_jq "pending payload carries no event" '.pending and (has("event") | not)'
FAKE_PR_AUTHOR=alice expect_exit 0 "pending review created" -- "$S/pr-review-submit" acme/docs#10 "$TMP/pending.json"
expect_jq "reported as pending, not submitted" '.pending and (.submitted | not)'
FAKE_REVIEWS="$ROOT/tests/fixtures/reviews-pending.json" FAKE_PR_AUTHOR=alice expect_exit 4 "refused when I already have a pending review" -- "$S/pr-review-submit" acme/docs#10 "$TMP/pending.json"
jq '.comments = [range(10) as $i | {path: "a.ts", line: ($i + 1), body: "point \($i)"}]' "$TMP/pending.json" >"$TMP/many.json"
FAKE_PR_AUTHOR=alice ADORNO_DRY_RUN=1 expect_exit 0 "more than max_inline comments" -- "$S/pr-review-submit" acme/docs#10 "$TMP/many.json"
expect_jq "8 inline, the rest moved to the body" '(.comments | length) == 8 and (.body | test("a.ts:9`: point 8")) and (.body | test("a.ts:10`: point 9"))'
expect_exit 0 "pending allowed on my own PR" -- env ADORNO_DRY_RUN=1 "$S/pr-review-submit" acme/docs#42 "$TMP/pending.json"

FAKE_PR_AUTHOR=alice FAKE_REVIEWS="$FAKE_FIX/reviews-pending.json" expect_exit 4 \
  "a pending review on a later page is found (pagination)" -- "$S/pr-review-submit" acme/docs#10 "$TMP/pending.json"
echo "pr-comment"
ADORNO_DRY_RUN=1 expect_exit 0 "dry-run comment" -- "$S/pr-comment" acme/docs#42 "$TMP/body.md"
expect_jq "body shown" '.dryRun and .body == "Fixed in abc123.\n"'
expect_exit 5 "comment needs L3" -- env ADORNO_LEVEL=L2 "$S/pr-comment" acme/docs#42 "$TMP/body.md"

echo "pr-merged and pr-deploys (impact reports)"
expect_exit 0 "merged PRs" -- "$S/pr-merged" acme/docs --since 2026-10-01
expect_jq "newest first, impact marker only counts when it is yours" \
  '[.[].number] == [42, 40] and .[0].impactReported == false and .[1].impactReported == true and .[0].files == ["api/users.ts", "client/list.tsx"] and .[0].mergeCommit == "m42"'
expect_exit 0 "relative period" -- "$S/pr-merged" acme/docs --since 30d
expect_exit 2 "bad period" -- "$S/pr-merged" acme/docs --since yesterday
expect_exit 3 "unregistered repo" -- "$S/pr-merged" nobody/repo
expect_exit 0 "one PR" -- "$S/pr-merged" acme/docs --pr 42
expect_jq "one PR as a list" 'length == 1 and .[0].number == 42'
expect_exit 0 "deployments after the merge that contain it" -- "$S/pr-deploys" acme/docs#42
expect_jq "first successful containing deploy per environment" \
  '.source == "github-deployments" and (.environments | map({environment, sha})) == [{"environment": "staging", "sha": "s1"}, {"environment": "production", "sha": "p2"}]'
expect_exit 0 "comment carries the impact report (dry run)" -- \
  env ADORNO_DRY_RUN=1 "$S/pr-comment" acme/docs#42 "$TMP/body.md"

printf '<!-- adorno:impact -->\n## Impact\n' >"$TMP/impact.md"
FAKE_PRIVATE=false expect_exit 4 "no impact report on a public repo" -- "$S/pr-comment" acme/docs#42 "$TMP/impact.md"
FAKE_PRIVATE=true ADORNO_DRY_RUN=1 expect_exit 0 "impact report on a private repo" -- "$S/pr-comment" acme/docs#42 "$TMP/impact.md"

echo "ci-failed, issue-fetch, pr-diff, review-merge"
expect_exit 0 "failed runs and their logs" -- "$S/ci-failed" acme/docs#42 50
expect_jq "failure and timeout kept, success dropped" '[.runs[].id] == [1, 2] and .headSha == "abc123"'
grep -q "expected 2, got 3" "$(jq -r '.runs[0].logFile' <<<"$out")" && ok "log tail saved" || ko "log tail saved"
[ ! -s "$(jq -r '.runs[1].logFile' <<<"$out")" ] && ok "a run without log gives an empty file, not an error" || ko "empty log"
expect_exit 2 "lines must be a number" -- "$S/ci-failed" acme/docs#42 lots
expect_exit 0 "issue" -- "$S/issue-fetch" acme/docs#7
expect_jq "issue flattened" '.author == "alice" and .labels == ["bug"] and .comments[0].author == "bob"'
expect_exit 0 "pr-diff" -- "$S/pr-diff" acme/docs#42
expect_jq "diff saved, files listed" '(.diffFile | test("\\.diff$")) and (.files | length) == 2 and .author == "octocat"'
mkdir -p "$TMP/reviews"
printf '{"agent":"agent:review:code","verdict":"fix","findings":[{"severity":"minor","file":"a.ts","line":3,"title":"Null not handled"}]}' >"$TMP/reviews/code.json"
printf '{"agent":"agent:review:back","verdict":"block","findings":[{"severity":"blocker","file":"a.ts","line":3,"title":" null  NOT handled"}]}' >"$TMP/reviews/back.json"
printf '{"nope":true}' >"$TMP/reviews/broken.json"
expect_exit 0 "review-merge" -- "$S/review-merge" "$TMP/reviews"
expect_jq "same finding merged, highest severity, both agents, broken file reported" \
  '.verdict == "block" and (.findings | length) == 1 and .findings[0].severity == "blocker" and .findings[0].agents == ["agent:review:back", "agent:review:code"] and .invalid == ["broken.json"]'
mkdir -p "$TMP/reviews2"
printf '{"agent":"agent:review:code","verdict":"pass","findings":[{"severity":"blocker","title":"Data loss"}]}' >"$TMP/reviews2/a.json"
printf '{"agent":"agent:review:back","verdict":"BLOCK","findings":[]}' >"$TMP/reviews2/b.json"
printf '{"agent":"agent:review:tests","findings":[]}' >"$TMP/reviews2/c.json"
expect_exit 0 "review-merge, inconsistent reviews" -- "$S/review-merge" "$TMP/reviews2"
expect_jq "a blocker forces block; unknown or missing verdicts are invalid, not pass" \
  '.verdict == "block" and .invalid == ["b.json", "c.json"]'

echo "pr-areas: tricky paths"
printf 'diff --git "a/client/\\303\\251 x.tsx" "b/client/\\303\\251 x.tsx"\n--- "a/client/\\303\\251 x.tsx"\n+++ "b/client/\\303\\251 x.tsx"\n@@ -1 +1 @@\n+const a = 1\ndiff --git a/server/old.ts b/server/old.ts\ndeleted file mode 100644\n--- a/server/old.ts\n+++ /dev/null\n@@ -1 +0,0 @@\n-x\n' >"$TMP/tricky.diff"
if [ -f "$REAL" ]; then
  jq '.repos["acme/app"] = {}' "$REAL" >"$TMP/areas2.json"
  reg "$TMP/areas2.json"
  expect_exit 0 "quoted, non-ASCII and deleted paths" -- "$S/pr-areas" acme/app "$TMP/tricky.diff"
  expect_jq "decoded paths in the right areas" '.areas.front == ["client/é x.tsx"] and .areas.back == ["server/old.ts"]'
  reg "$ROOT/tests/fixtures/repos.json"
fi

echo "pr-workspace and pr-push (local git plays GitHub)"
W="$TMP/upstream"; O="$TMP/origin.git"
git init -q -b main "$W"; git -C "$W" config user.email t@t; git -C "$W" config user.name t
echo one >"$W/a.txt"; git -C "$W" add a.txt; git -C "$W" commit -qm "base"
basesha="$(git -C "$W" rev-parse HEAD)"
git -C "$W" checkout -qb nm/pagination; echo two >>"$W/a.txt"; git -C "$W" commit -qam "feat: two"
headsha="$(git -C "$W" rev-parse HEAD)"
git clone -q --bare "$W" "$O"; git -C "$O" update-ref refs/pull/42/head "$headsha"
export FAKE_ORIGIN="$O" FAKE_HEAD_SHA="$headsha"

expect_exit 0 "creates the workspace" -- "$S/pr-workspace" acme/docs#42
expect_jq "detached at the PR head, diff base = merge-base" \
  ".headSha == \"$headsha\" and .diffBase == \"$basesha\" and .changedFiles == 1 and .mine"
ws="$(jq -r .dir <<<"$out")"
[ "$(git -C "$ws" rev-parse HEAD)" = "$headsha" ] && ok "workspace HEAD is the PR head" || ko "workspace HEAD is the PR head"
case "$ws" in "$KH/workspaces/acme__docs/pr-42") ok "lives under the kit home" ;; *) ko "lives under the kit home" "$ws" ;; esac

git -C "$ws" config user.email t@t; git -C "$ws" config user.name t
mkdir -p "$ws/.agent-run/x"; echo notes >"$ws/.agent-run/x/status.md"
[ -z "$(git -C "$ws" status --porcelain)" ] && ok ".agent-run is ignored by git" || ko ".agent-run is ignored by git"
echo three >>"$ws/a.txt"
expect_exit 4 "push refused with uncommitted changes" -- "$S/pr-push" acme/docs#42
git -C "$ws" commit -qam "fix: three"
expect_exit 4 "refresh refused with unpushed commits" -- "$S/pr-workspace" acme/docs#42
FAKE_PR_AUTHOR=alice expect_exit 4 "push refused on someone else's PR" -- "$S/pr-push" acme/docs#42
FAKE_CROSS=true expect_exit 4 "push refused from a fork" -- "$S/pr-push" acme/docs#42
expect_exit 5 "push needs L2" -- env ADORNO_LEVEL=L1 "$S/pr-push" acme/docs#42
expect_exit 0 "pushes to the PR branch" -- "$S/pr-push" acme/docs#42
expect_jq "one commit pushed" '.pushed and .commits == 1'

echo "guard_bash (the Claude Code hook)"
guard() {  # guard WANT COMMAND — the decision the hook takes for COMMAND (pass = none)
  local got
  got="$(jq -n --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}}' | python3 "$S/guard_bash.py" deny \
    | jq -r '.hookSpecificOutput.permissionDecision // "pass"' 2>/dev/null)"
  [ -n "$got" ] || got=pass
  if [ "$got" = "$1" ]; then ok "guard: $1 · $2"; else ko "guard: $1 · $2" "got $got"; fi
}
guard deny "git push origin fix/x"
guard deny "git -C ../other push --force"
guard deny "cd app && env FOO=1 git push"
guard deny "bash -c 'sudo -u me git push'"
guard deny "gh -R acme/docs pr comment 42 -b hi"
guard deny "gh api repos/acme/docs/issues/42/comments -f body=hi"
guard deny "gh api graphql -f query='mutation { resolveReviewThread(input: {}) { clientMutationId } }'"
guard deny "curl -X POST https://api.github.com/repos/acme/docs/issues"
guard deny "echo '{}' > ~/.adorno/runs/active/x.json"
guard deny "HOME=/tmp/h ~/.claude/skills/adorno-github/scripts/pr-comment acme/docs#42 f.md"
guard pass "git commit -m 'push the fix'"
guard pass "gh pr view 42 --json title"
guard pass "gh api graphql -f query='{ viewer { login } }'"
guard pass "cat ~/.adorno/registry.json"
guard pass ".claude/skills/adorno-github/scripts/run-end 2026-x"
guard pass "npm test"
guard ask "echo 'unbalanced"
out="$(jq -n '{tool_name: "Bash", tool_input: {command: "git push"}}' | python3 "$S/guard_bash.py" ask)"
expect_jq "a global install asks instead" '.hookSpecificOutput.permissionDecision == "ask"'

echo "with_lock"
cat >"$TMP/lock-test" <<EOF
#!/usr/bin/env bash
. "$S/_lib.sh"
mkdir -p "\$(kit_home)/locks/dead.lock"; echo 999999 >"\$(kit_home)/locks/dead.lock/pid"
with_lock dead true; echo "took over a dead holder's lock"
steps() { false; echo "continued after a failing step"; }
with_lock t steps
echo "returned 0"
EOF
chmod +x "$TMP/lock-test"
out="$("$TMP/lock-test" 2>&1)"; got=$?
case "$out" in *continued*|*"returned 0"*) ko "a failing step fails the locked command" "$out" ;; *) [ "$got" = 1 ] && ok "a failing step fails the locked command" || ko "a failing step fails the locked command" "exit $got" ;; esac
grep -q "took over" <<<"$out" && ok "a lock whose holder died is taken over at once" || ko "a lock whose holder died is taken over at once" "$out"
[ ! -e "$KH/locks/t.lock" ] && ok "the lock is released" || ko "the lock is released"

echo "git-push (a branch without PR)"
C="$TMP/clone"; git clone -q "$O" "$C"; git -C "$C" config user.email t@t; git -C "$C" config user.name t
git -C "$C" config "url.file://$O.insteadOf" "git@github.com:acme/docs.git"
git -C "$C" remote set-url origin "git@github.com:acme/docs.git"
git -C "$C" checkout -qb feat/lem-7-empty-pages; echo x >"$C/b.txt"; git -C "$C" add b.txt; git -C "$C" commit -qm "feat: b"
expect_exit 0 "pushes a conforming branch" -- "$S/git-push" acme/docs feat/lem-7-empty-pages --dir "$C"
expect_jq "pushed" '.pushed and .branch == "feat/lem-7-empty-pages"'
[ "$(git -C "$O" rev-parse feat/lem-7-empty-pages)" = "$(git -C "$C" rev-parse HEAD)" ] && ok "branch on origin" || ko "branch on origin"
git -C "$C" checkout -q main
expect_exit 4 "never the base branch" -- "$S/git-push" acme/docs main --dir "$C"
git -C "$C" checkout -qb wip; git -C "$C" commit -q --allow-empty -m "wip"
expect_exit 4 "a name outside branch_pattern is refused" -- "$S/git-push" acme/docs wip --dir "$C"
expect_exit 4 "the origin must be the repo named" -- "$S/git-push" acme/strict wip --dir "$C"
git -C "$C" config remote.origin.pushurl "git@github.com:evil/docs.git"
expect_exit 4 "a pushurl to another repo is refused" -- "$S/git-push" acme/docs fix/lem-8-x --dir "$C"
git -C "$C" config --unset remote.origin.pushurl
git -C "$C" checkout -qb fix/lem-8-x
expect_exit 5 "needs L2" -- env ADORNO_LEVEL=L1 "$S/git-push" acme/docs --dir "$C"
ADORNO_DRY_RUN=1 expect_exit 0 "dry run only prints" -- "$S/git-push" acme/docs --dir "$C"
expect_jq "dry run" '.dryRun and .branch == "fix/lem-8-x"'

[ "$(git -C "$O" rev-parse nm/pagination)" = "$(git -C "$ws" rev-parse HEAD)" ] && ok "origin branch moved" || ko "origin branch moved"
expect_exit 0 "nothing new to push" -- "$S/pr-push" acme/docs#42
expect_jq "reported as nothing new" '(.pushed | not)'

git -C "$W" pull -q "$O" nm/pagination; echo four >>"$W/a.txt"; git -C "$W" commit -qam "feat: someone else"
git -C "$W" push -q "$O" nm/pagination
echo five >>"$ws/a.txt"; git -C "$ws" commit -qam "fix: five"
expect_exit 1 "non-fast-forward push rejected, never forced" -- "$S/pr-push" acme/docs#42
git -C "$ws" reset -q --hard "refs/adorno/pr-42"

newsha="$(git -C "$O" rev-parse nm/pagination)"; git -C "$O" update-ref refs/pull/42/head "$newsha"
FAKE_HEAD_SHA="$newsha" expect_exit 0 "refresh follows the new head" -- "$S/pr-workspace" acme/docs#42
[ "$(git -C "$ws" rev-parse HEAD)" = "$newsha" ] && ok "workspace moved to the new head" || ko "workspace moved to the new head"
FAKE_PR_STATE=MERGED expect_exit 0 "clean removes merged PRs' workspaces" -- "$S/pr-workspace" --clean
expect_jq "workspace removed" '(.removed | length) == 1'
[ ! -d "$ws" ] && ok "directory gone" || ko "directory gone"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
