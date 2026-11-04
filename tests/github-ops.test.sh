#!/usr/bin/env bash
# Tests for src/skills/github-ops/scripts against a fake `gh`. No network.
# Usage: tests/github-ops.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/src/skills/github-ops/scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"; ln -s "$ROOT/tests/fake-gh" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" ADORNO_REPOS="$ROOT/tests/fixtures/repos.json"
export FAKE_FIX="$ROOT/tests/fixtures" AGENT_RUN_DIR="$TMP/run" FAKE_LOG="$TMP/gh.log" GH_OPS_POLL=0
unset ADORNO_LEVEL GH_OPS_DRY_RUN

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

echo "registry and usage"
expect_exit 3 "unregistered repo is refused" -- "$S/pr-feedback-fetch" foo/bar#1
expect_exit 2 "missing PR number is a usage error" -- "$S/pr-feedback-fetch" acme/docs
expect_exit 0 "repo-conf merges defaults" -- "$S/repo-conf" acme/strict
expect_jq "repo-conf: repo value wins, base filled from GitHub" \
  '.resolve_threads == "reviewer" and .reply_language == "en" and .base == "main"'

for url in git@github.com:acme/strict.git https://github.com/acme/strict ssh://git@github.com/acme/strict.git; do
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
GH_OPS_DRY_RUN=1 expect_exit 0 "dry-run reply" -- "$S/pr-reply" acme/docs#42 T1 "$TMP/body.md"
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

GH_OPS_DRY_RUN=1 expect_exit 0 "rerequest defaults to past human reviewers" -- "$S/pr-rerequest" acme/docs#42
expect_jq "bots and myself excluded, deduplicated" '.reviewers == ["alice","bob"]'
expect_exit 0 "rerequest named reviewer" -- "$S/pr-rerequest" acme/docs#42 carol
expect_jq "requested carol" '.requested == ["carol"]'

echo "pr-open"
expect_exit 2 "non-conventional title refused" -- "$S/pr-open" acme/docs feat/lem-1-x "Add stuff" "$TMP/body.md"
expect_exit 4 "branch outside branch_pattern refused" -- "$S/pr-open" acme/docs nm/lem-1-x "feat: add stuff" "$TMP/body.md"
GH_OPS_DRY_RUN=1 expect_exit 0 "dry-run open" -- "$S/pr-open" acme/docs feat/lem-123-pagination "feat(api)!: add stuff" "$TMP/body.md" --draft
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
GH_OPS_DRY_RUN=1 expect_exit 0 "first rerun allowed" -- "$S/ci-rerun" acme/docs 123

echo "pr-review-requested"
expect_exit 0 "lists review requests" -- "$S/pr-review-requested"
expect_jq "direct request detected" '(.[] | select(.number==10) | .direct) == true'
expect_jq "team request kept, not direct" '(.[] | select(.number==11) | (.direct | not) and .viaTeams == ["backend"])'
expect_jq "already reviewed head flagged and sorted last" '.[-1].number == 11 and .[-1].reviewedHead'
expect_jq "unregistered repo flagged" '(.[] | select(.number==12) | .registered) == false'
expect_jq "my pending review is surfaced" '(.[] | select(.number==10) | .pendingReview) and ((.[] | select(.number==11) | .pendingReview) | not)'

echo "pr-areas (public default rules from repos.yaml)"
REAL="$ROOT/dist/claude/.claude/skills/github-ops/repos.json"
if [ -f "$REAL" ]; then
  jq '.repos = {"acme/app": {}, "acme/docs": {"area_reviewers": {"docs": ["agent:review:security"]}}}' "$REAL" >"$TMP/areas-repos.json"
  ADORNO_REPOS="$TMP/areas-repos.json" expect_exit 0 "classifies a diff" -- "$S/pr-areas" acme/app "$ROOT/tests/fixtures/sample.diff"
  expect_jq "front by extension" '.areas.front == ["client/app.tsx"]'
  expect_jq "mongodb by added-line content" '.areas.mongodb == ["server/users.js"] and .areas.back == ["server/users.js"]'
  expect_jq "deps and docs" '.areas.deps == ["package.json"] and .areas.docs == ["README.md"]'
  expect_jq "unmatched files land in other" '.other == ["notes/weird.txt"]'
  expect_jq "reviewers: always + per area, deduplicated" \
    '(.reviewers | sort) == (["agent:review:code","agent:review:ponytail","agent:review:front","agent:review:perf","agent:review:back","agent:review:tests","agent:review:mongodb","agent:review:security"] | sort)'
  ADORNO_REPOS="$TMP/areas-repos.json" expect_exit 0 "per-repo override" -- "$S/pr-areas" acme/docs "$ROOT/tests/fixtures/sample.diff"
  expect_jq "override merges with default areas" '.areas.front == ["client/app.tsx"] and (.reviewers | index("agent:review:security"))'
  jq -e '.repos == {}' "$REAL" >/dev/null && ok "public registry has no repos" || ko "public registry has no repos"
else
  ko "pr-areas tests need dist/ — run bin/kit build first"
fi

echo "pr-review-submit"
printf '%s' '{"event":"COMMENT","body":"Looks good overall.","comments":[{"path":"a.ts","line":3,"body":"Null check?"}]}' >"$TMP/review.json"
FAKE_PR_AUTHOR=alice GH_OPS_DRY_RUN=1 expect_exit 0 "dry-run review" -- "$S/pr-review-submit" acme/docs#10 "$TMP/review.json"
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
FAKE_PR_AUTHOR=alice GH_OPS_DRY_RUN=1 expect_exit 0 "no event means a pending review" -- "$S/pr-review-submit" acme/docs#10 "$TMP/pending.json"
expect_jq "pending payload carries no event" '.pending and (has("event") | not)'
FAKE_PR_AUTHOR=alice expect_exit 0 "pending review created" -- "$S/pr-review-submit" acme/docs#10 "$TMP/pending.json"
expect_jq "reported as pending, not submitted" '.pending and (.submitted | not)'
FAKE_REVIEWS="$ROOT/tests/fixtures/reviews-pending.json" FAKE_PR_AUTHOR=alice expect_exit 4 "refused when I already have a pending review" -- "$S/pr-review-submit" acme/docs#10 "$TMP/pending.json"
jq '.comments = [range(10) as $i | {path: "a.ts", line: ($i + 1), body: "point \($i)"}]' "$TMP/pending.json" >"$TMP/many.json"
FAKE_PR_AUTHOR=alice GH_OPS_DRY_RUN=1 expect_exit 0 "more than max_inline comments" -- "$S/pr-review-submit" acme/docs#10 "$TMP/many.json"
expect_jq "8 inline, the rest moved to the body" '(.comments | length) == 8 and (.body | test("a.ts:9`: point 8")) and (.body | test("a.ts:10`: point 9"))'
expect_exit 0 "pending allowed on my own PR" -- env GH_OPS_DRY_RUN=1 "$S/pr-review-submit" acme/docs#42 "$TMP/pending.json"

echo "pr-comment"
GH_OPS_DRY_RUN=1 expect_exit 0 "dry-run comment" -- "$S/pr-comment" acme/docs#42 "$TMP/body.md"
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
  env GH_OPS_DRY_RUN=1 "$S/pr-comment" acme/docs#42 "$TMP/body.md"

echo "pr-workspace and pr-push (local git plays GitHub)"
W="$TMP/upstream"; O="$TMP/origin.git"
git init -q -b main "$W"; git -C "$W" config user.email t@t; git -C "$W" config user.name t
echo one >"$W/a.txt"; git -C "$W" add a.txt; git -C "$W" commit -qm "base"
basesha="$(git -C "$W" rev-parse HEAD)"
git -C "$W" checkout -qb nm/pagination; echo two >>"$W/a.txt"; git -C "$W" commit -qam "feat: two"
headsha="$(git -C "$W" rev-parse HEAD)"
git clone -q --bare "$W" "$O"; git -C "$O" update-ref refs/pull/42/head "$headsha"
export FAKE_ORIGIN="$O" FAKE_HEAD_SHA="$headsha" ADORNO_HOME="$TMP/kit-home"

expect_exit 0 "creates the workspace" -- "$S/pr-workspace" acme/docs#42
expect_jq "detached at the PR head, diff base = merge-base" \
  ".headSha == \"$headsha\" and .diffBase == \"$basesha\" and .changedFiles == 1 and .mine"
ws="$(jq -r .dir <<<"$out")"
[ "$(git -C "$ws" rev-parse HEAD)" = "$headsha" ] && ok "workspace HEAD is the PR head" || ko "workspace HEAD is the PR head"
case "$ws" in "$TMP/kit-home/workspaces/acme__docs/pr-42") ok "lives under the kit home" ;; *) ko "lives under the kit home" "$ws" ;; esac

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
