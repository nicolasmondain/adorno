#!/usr/bin/env bash
# Tests for bench/: the cases (valid, each diff applies to its base) and their routing by pr-areas with the public
# default areas. No model is called, no network.
# Usage: tests/bench.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="$ROOT/bench"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# _lib.sh wants a `gh` on the PATH (pr-areas never calls it), and reads the registry from ~/.adorno only
mkdir -p "$TMP/bin"; ln -s "$ROOT/tests/fake-gh" "$TMP/bin/gh"
export HOME="$TMP/home" PATH="$TMP/bin:$PATH"
KH="$HOME/.adorno"; mkdir -p "$KH"

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko()   { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
# expect_exit CODE NAME -- cmd...
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err" </dev/null)"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(tail -c 400 "$TMP/err")"; fi
}
expect_jq() {  # expect_jq NAME FILTER (evaluated on $out, must be true)
  if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $(head -c 600 <<<"$out")"; fi
}

echo "cases"
# the shape of case.json: what bench/route, the runner and the scoring read
VALID='
  def text: type == "string" and length > 0;
  def among($set): . as $v | $set | index($v) != null;
  (.title | text) and (.description | text) and (.rationale | text)
  and (.routing.areas | type == "array" and length > 0 and all(.[]; text))
  and (.routing.review | type == "array" and length > 0 and all(.[]; text and startswith("agent:review:")))
  and (.routing.skills // [] | type == "array" and all(.[]; text))
  and (.verdict | type == "array" and length > 0 and all(.[]; among(["pass", "fix", "block"])))
  and (.findings | type == "array")
  and (.routing.review as $review | all(.findings[];
        (.file | text)
        and (.lines == null or (.lines | type == "array" and length == 2 and .[0] >= 1 and .[0] <= .[1]))
        and (.category | text)
        and (.severity | type == "array" and length > 0 and all(.[]; among(["blocker", "major", "minor", "question"])))
        and (.keywords | type == "array" and length > 0 and all(.[]; text))
        and (.reviewer | among($review))))
  and (.findings != [] or .verdict == ["pass"])'
n=0
for dir in "$B"/cases/*/; do
  dir="${dir%/}"; id="$(basename "$dir")"; n=$((n + 1))
  if jq -e "$VALID" "$dir/case.json" >/dev/null 2>&1; then ok "$id: case.json is valid"; else ko "$id: case.json is valid"; fi
  ws="$TMP/ws/$id"; mkdir -p "$TMP/ws"; cp -R "$dir/base" "$ws"
  if (cd "$ws" && git init -q . && git apply --check "$dir/change.diff" && git apply "$dir/change.diff") 2>"$TMP/err"; then
    ok "$id: change.diff applies to base/"
  else
    ko "$id: change.diff applies to base/" "$(tail -c 400 "$TMP/err")"
  fi
  # an expected finding points at a file of the diff, on lines the changed file has
  bad="$(jq -r '.findings[] | "\(.file)\t\(.lines // [1, 1] | .[1])"' "$dir/case.json" | while IFS=$'\t' read -r f last; do
    if ! grep -qx "+++ b/$f" "$dir/change.diff" || [ ! -f "$ws/$f" ] || [ "$(wc -l <"$ws/$f")" -lt "$last" ]; then
      printf '%s:%s ' "$f" "$last"
    fi
  done)"
  if [ -z "$bad" ]; then ok "$id: expected findings are in the change"; else ko "$id: expected findings are in the change" "$bad"; fi
done
if [ "$n" -ge 12 ]; then ok "the first set is there ($n cases)"; else ko "the first set is there" "$n cases"; fi

echo "routing (public default rules from repos.yaml)"
REAL="$ROOT/dist/claude/.claude/skills/adorno-github/repos.json"
if [ -f "$REAL" ]; then
  jq '.repos = {"adorno/bench": {}}' "$REAL" >"$KH/registry.json"
  expect_exit 0 "every case routes as its case.json says" -- "$B/route"
  expect_jq "one entry per case, all ok, each with the full pr-areas output" \
    "length == $n and all(.[]; .ok and (.routed.review | length) >= 2 and (.routed.by_area | type) == \"object\")"
  expect_exit 0 "--case filters" -- "$B/route" --case docs-only --case front-a11y
  expect_jq "only the cases asked for, in that order" 'map(.case) == ["docs-only", "front-a11y"]'
  expect_jq "docs only: the docs area and the always reviewers, nothing else" \
    '(.[0].routed.areas | keys) == ["docs"] and .[0].routed.review == ["agent:review:code", "agent:review:ponytail"]'

  mkdir -p "$TMP/cases"; cp -R "$B/cases/docs-only" "$TMP/cases/reviewer"; cp -R "$B/cases/docs-only" "$TMP/cases/skill"
  jq '.routing.review += ["agent:review:security"]' "$B/cases/docs-only/case.json" >"$TMP/cases/reviewer/case.json"
  jq '.routing.skills += ["typescript-pro"]' "$B/cases/docs-only/case.json" >"$TMP/cases/skill/case.json"
  expect_exit 1 "a case whose routing differs fails" -- "$B/route" --cases "$TMP/cases"
  expect_jq "a reviewer pr-areas does not pick" \
    '(.[] | select(.case == "reviewer") | (.ok | not) and (.review.want | index("agent:review:security")) and (.review.got | index("agent:review:security") | not))'
  expect_jq "a skill pr-areas does not pick" '(.[] | select(.case == "skill") | (.ok | not) and .skills_missing == ["typescript-pro"])'
  if grep -q "reviewer, skill" "$TMP/err"; then ok "the failing cases are named"; else ko "the failing cases are named" "$(cat "$TMP/err")"; fi

  expect_exit 2 "unknown case" -- "$B/route" --case nope
  expect_exit 2 "unknown option" -- "$B/route" --nope x
  expect_exit 3 "a repo the registry does not declare" -- "$B/route" --repo acme/unknown --case docs-only
else
  ko "routing tests need dist/ — run bin/kit build first"
fi

echo "runner (a fake claude plays the agents: no model, no network)"
ln -s "$ROOT/tests/fake-claude" "$TMP/bin/claude"
FK="$TMP/fake"; R="$TMP/results"; mkdir -p "$FK" "$TMP/tmp"
export FAKE_CLAUDE_ENVELOPE="$ROOT/tests/fixtures/bench/claude-result.json" FAKE_CLAUDE_LOG="$TMP/claude.log" FAKE_CLAUDE_DIR="$FK"
export FAKE_FIX="$ROOT/tests/fixtures" FAKE_LOG="$TMP/gh.log" TMPDIR="$TMP/tmp" FAKE_CLAUDE_COMMITS="$TMP/commits"
calls() { out="$(jq -s '.' "$FAKE_CLAUDE_LOG")"; : >"$FAKE_CLAUDE_LOG"; }  # the calls since the last look, into $out
if [ -f "$REAL" ]; then
  printf '{"agent":"agent:review:mongodb","verdict":"fix","findings":[{"severity":"major","file":"server/services/orders.ts","line":36,"title":"N+1: one query per order","detail":"findOne in a loop","fix":"one $in query"}]}' >"$FK/mongodb.json"
  printf '{"body":"One point.","comments":[{"path":"server/services/orders.ts","line":36,"side":"RIGHT","body":"issue (non-blocking): one query per order."}]}' >"$FK/adorno.final.json"
  expect_exit 0 "two cases end to end" -- "$B/run" --case docs-only --case mongo-n-plus-one --label first --results "$R"
  expect_jq "the run is described" \
    '.label == "first" and .tool == "claude" and .model == null and .repo == "adorno/bench" and .repeat == 1 and .cases == ["docs-only", "mongo-n-plus-one"] and (.prompts.sha | type) == "string" and (.tool_version | test("fake")) and .skipped == [] and (.runs | length) == 2'
  # docs-only: 2 reviewers + adorno; mongo-n-plus-one: 6 reviewers + adorno; 0.01 a call
  expect_jq "its cost is the sum of what the tool reported" '(.cost_usd * 100 | round) == 10'
  D="$R/first/mongo-n-plus-one/1"
  out="$(cat "$D/review.json")"
  expect_jq "the reviews are merged by review-merge" '.verdict == "fix" and .counts.major == 1 and .invalid == [] and (.agents | length) == 6'
  out="$(cat "$D/run.json")"
  expect_jq "the case run is described" \
    '.case == "mongo-n-plus-one" and .routing_ok and .missing == [] and .invalid == [] and .verdict == "fix" and (.diff_base | length) == 40 and (.budget_exhausted | not) and (.cost_usd * 100 | round) == 7'
  out="$(cat "$D/meta/mongodb.json")"
  expect_jq "per agent: the model actually used, tokens, cost, duration" \
    '.agent == "agent:review:mongodb" and .models == ["fake-tier-model"] and .tokens == {"input": 1554, "cache_read": 49887, "cache_write": 18571, "output": 1902} and .cost_usd == 0.01 and .duration_ms > 0 and .attempts == 1 and .delivered == "file" and (.is_error | not)'
  if [ -f "$D/review-final.json" ] && [ -f "$D/review-notes.md" ] && [ -f "$D/areas.json" ] && [ -f "$D/meta/adorno.json" ] \
    && [ -f "$D/messages/mongodb.md" ] && [ "$(find "$D/reviews" -name '*.json' | wc -l)" -eq 6 ] \
    && [ "$(find "$R/first/docs-only/1/reviews" -name '*.json' | wc -l)" -eq 2 ]; then
    ok "one review per reviewer, the adorno pass, the routing and the messages are kept"
  else
    ko "one review per reviewer, the adorno pass, the routing and the messages are kept" "$(find "$R/first" -type f | head -40)"
  fi
  if [ "$(cat "$FAKE_CLAUDE_COMMITS")" = "feat(orders): list orders with the customer name"$'\n'"chore: initial commit" ]; then
    ok "the workspace holds the base, then the change committed under the case's title"
  else
    ko "the workspace holds the base, then the change committed under the case's title" "$(cat "$FAKE_CLAUDE_COMMITS")"
  fi
  calls
  expect_jq "one call per reviewer, then agent:adorno" \
    'length == 10 and ([.[] | .[index("--agent") + 1]] | .[2] == "adorno:adorno" and .[-1] == "adorno:adorno" and (index("adorno:adorno-agent-review-perf-back") != null))'
  expect_jq "the prompts of the working tree, user settings left out, sandboxed, no permission bypass" \
    'all(.[]; (.[index("--plugin-dir") + 1] | endswith("dist/claude-plugin")) and .[index("--setting-sources") + 1] == "project,local" and .[index("--permission-mode") + 1] == "dontAsk" and (.[index("--settings") + 1] | fromjson | .sandbox.enabled and (.sandbox.allowUnsandboxedCommands | not) and (.autoMemoryEnabled | not)) and (index("--dangerously-skip-permissions") == null) and (index("--model") == null) and (index("--max-budget-usd") == null))'
  expect_jq "a reviewer gets diffBase, the files of its area and the skills of the areas they fall in" \
    '(.[] | select(.[index("--agent") + 1] == "adorno:adorno-agent-review-mongodb") | .[1]) | test("diffBase: `[0-9a-f]{40}`") and test("Files of your area: server/services/orders.test.ts, server/services/orders.ts\n") and test("Skills of your areas: typescript-pro, test-driven-development\n") and test("reviews/mongodb.json")'
  expect_jq "an always reviewer gets every file" \
    '[.[] | select(.[index("--agent") + 1] == "adorno:adorno-agent-review-ponytail") | .[1]] | length == 2 and (.[0] | test("Files of your area: README.md\n") and test("Skills of your areas: documentation-and-adrs\n")) and (.[1] | test("Files of your area: server/services/orders.test.ts, server/services/orders.ts\n"))'
  expect_jq "agent:adorno gets the merged review" '.[-1][1] | test("Situation 2") and test(".agent-run/review/review.json")'

  expect_exit 0 "--repeat and --model" -- "$B/run" --case docs-only --repeat 2 --model some-model --label twice --results "$R"
  if [ -f "$R/twice/docs-only/1/run.json" ] && [ -f "$R/twice/docs-only/2/run.json" ]; then ok "one folder per repeat"; else ko "one folder per repeat"; fi
  out="$(cat "$R/twice/docs-only/2/meta/code.json")"
  expect_jq "the model that ran is recorded" '.models == ["some-model"]'
  calls
  expect_jq "--model reaches every call" 'length == 6 and all(.[]; .[index("--model") + 1] == "some-model")'

  printf '{"nope":true}' >"$FK/back.first.json"
  expect_exit 0 "a malformed review" -- "$B/run" --case clean-refactor --label retry --results "$R"
  out="$(cat "$R/retry/clean-refactor/1/meta/back.json")"
  expect_jq "is run once more, both attempts counted" '.attempts == 2 and .delivered == "file" and (.cost_usd * 100 | round) == 2 and .tokens.output == 3804'
  out="$(cat "$R/retry/clean-refactor/1/run.json")"
  expect_jq "and nothing invalid is left" '.invalid == [] and .missing == []'
  rm "$FK/back.first.json"; printf '{"nope":true}' >"$FK/back.json"; calls
  expect_exit 0 "a review malformed twice" -- "$B/run" --case clean-refactor --label invalid --results "$R"
  out="$(cat "$R/invalid/clean-refactor/1/run.json")"
  expect_jq "stays invalid after one retry, the run goes on" '.invalid == ["back.json"] and .missing == []'
  rm "$FK/back.json"; calls
  expect_jq "one retry, not more" '[.[] | select(.[index("--agent") + 1] == "adorno:adorno-agent-review-back")] | length == 2'

  printf 'I could not write the file. Here it is:\n```json\n{"agent":"agent:review:tests","verdict":"pass","findings":[]}\n```\nVerdict: pass.\n' >"$FK/tests.message"
  expect_exit 0 "a review given in the message instead of the file" -- "$B/run" --case clean-refactor --label salvage --results "$R"
  out="$(cat "$R/salvage/clean-refactor/1/meta/tests.json")"
  expect_jq "is salvaged, and recorded as such" '.delivered == "salvaged" and .attempts == 1'
  out="$(cat "$R/salvage/clean-refactor/1/review.json")"
  expect_jq "and merged with the others" '.invalid == [] and (.agents | index("agent:review:tests") != null)'
  printf 'I could not write the review.\n' >"$FK/tests.message"
  expect_exit 0 "a review that never comes" -- "$B/run" --case clean-refactor --label none --results "$R"
  out="$(cat "$R/none/clean-refactor/1/run.json")"
  expect_jq "is reported missing" '.missing == ["agent:review:tests"]'
  out="$(cat "$R/none/clean-refactor/1/meta/tests.json")"
  expect_jq "after one retry" '.delivered == "none" and .attempts == 2'
  rm "$FK/tests.message"; calls

  expect_exit 0 "a budget" -- "$B/run" --case docs-only --repeat 3 --budget-usd 0.05 --label budget --results "$R"
  expect_jq "stops the run before the case that would exceed it" \
    '(.runs | length) == 1 and .skipped == [{"case": "docs-only", "n": 2, "reason": "budget"}, {"case": "docs-only", "n": 3, "reason": "budget"}] and .budget_usd == 0.05'
  if grep -q "2 case run(s) skipped" "$TMP/err"; then ok "and says so"; else ko "and says so" "$(cat "$TMP/err")"; fi
  calls
  expect_jq "each call is capped by what is left" \
    'length == 3 and ([.[] | .[index("--max-budget-usd") + 1] | tonumber] | .[0] == 0.025 and .[2] == 0.03)'
  export FAKE_CLAUDE_COST=0.03
  expect_exit 0 "a budget spent by the reviewers" -- "$B/run" --case docs-only --budget-usd 0.05 --label spent --results "$R"
  out="$(cat "$R/spent/docs-only/1/run.json")"
  expect_jq "is reported on the case run" '.budget_exhausted'
  if [ ! -e "$R/spent/docs-only/1/meta/adorno.json" ]; then ok "and agent:adorno is not started"; else ko "and agent:adorno is not started"; fi
  unset FAKE_CLAUDE_COST; calls

  expect_exit 0 "a routing that differs from case.json" -- "$B/run" --cases "$TMP/cases" --case reviewer --label drift --results "$R"
  out="$(cat "$R/drift/reviewer/1/run.json")"
  expect_jq "is recorded, and the run goes on with what pr-areas picked" '(.routing_ok | not) and .missing == []'

  expect_exit 2 "a label already used" -- "$B/run" --case docs-only --label first --results "$R"
  expect_exit 2 "unknown case" -- "$B/run" --case nope --label x --results "$R"
  expect_exit 2 "unknown tool" -- "$B/run" --tool nope --label x --results "$R"
  expect_exit 2 "unknown option" -- "$B/run" --nope
  expect_exit 3 "a repo the registry does not declare" -- "$B/run" --repo acme/unknown --case docs-only --label x --results "$R"
  if [ ! -e "$R/x" ]; then ok "a refused run writes nothing"; else ko "a refused run writes nothing"; fi
  if [ -z "$(ls -A "$TMPDIR")" ]; then ok "the workspaces are removed"; else ko "the workspaces are removed" "$(ls -A "$TMPDIR")"; fi
  if [ ! -s "$FAKE_LOG" ]; then ok "gh is never called"; else ko "gh is never called" "$(cat "$FAKE_LOG")"; fi
else
  ko "runner tests need dist/ — run bin/kit build first"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
