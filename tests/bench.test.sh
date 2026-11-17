#!/usr/bin/env bash
# Tests for bench/: the cases (valid, each diff applies to its base), their routing by pr-areas with the public
# default areas, the runner against a fake `claude`, the scoring and the report on fixed results. No model is called,
# no network.
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
  and (.extras // [] | type == "array" and all(.[];
        (.file | text) and (.lines == null or (.lines | type == "array" and length == 2 and .[0] >= 1 and .[0] <= .[1]))
        and (.keywords | type == "array" and length > 0 and all(.[]; text)) and (.valid | type == "boolean")))
  and (.findings != [] or .verdict == ["pass"])
  and (.kind // "review" | among(["review", "adorno"]))
  and (if .kind == "adorno" then .planted | type == "array" and length > 0 and all(.[];
          (.file | text) and (.lines == null or (.lines | type == "array" and length == 2 and .[0] >= 1 and .[0] <= .[1]))
          and (.keywords | type == "array" and length > 0 and all(.[]; text)) and (.why | text))
       else has("planted") | not end)'
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
# a case of kind adorno brings one valid review per routed reviewer, where every expected and planted finding is
HIT='def hit($m; $e): any($m.findings[]; .file == $e.file
       and ($e.lines == null or (.line != null and .line >= $e.lines[0] - 3 and .line <= $e.lines[1] + 3))
       and ("\(.title) \(.detail // "") \(.fix // "")" as $t | any($e.keywords[]; . as $k | $t | test($k; "i"))));'
adorno_cases=0
for dir in "$B"/cases/*/; do
  dir="${dir%/}"; id="$(basename "$dir")"
  [ "$(jq -r '.kind // "review"' "$dir/case.json")" = adorno ] || continue
  adorno_cases=$((adorno_cases + 1))
  want="$(jq -r '[.routing.review[] | split(":")[-1] + ".json"] | sort | join(" ")' "$dir/case.json")"
  got="$(find "$dir/reviews" -name '*.json' -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')"
  if [ "$got" = "$want " ]; then ok "$id: one review per routed reviewer"; else ko "$id: one review per routed reviewer" "want $want, got $got"; fi
  merged="$("$ROOT/src/skills/adorno-github/scripts/review-merge" "$dir/reviews")"
  if jq -e --slurpfile c "$dir/case.json" "$HIT"' . as $m | .invalid == [] and all($c[0].findings[]; hit($m; .)) and all($c[0].planted[]; hit($m; .))' <<<"$merged" >/dev/null; then
    ok "$id: the reviews are valid and hold every expected and planted finding"
  else
    ko "$id: the reviews are valid and hold every expected and planted finding" "$(head -c 400 <<<"$merged")"
  fi
  bad="$(jq -r '.planted[] | "\(.file)\t\(.lines // [1, 1] | .[1])"' "$dir/case.json" | while IFS=$'\t' read -r f last; do
    [ -f "$TMP/ws/$id/$f" ] && [ "$(wc -l <"$TMP/ws/$id/$f")" -ge "$last" ] || printf '%s:%s ' "$f" "$last"
  done)"
  if [ -z "$bad" ]; then ok "$id: planted findings point into the changed repo"; else ko "$id: planted findings point into the changed repo" "$bad"; fi
done
# a planted finding may sit outside the change: agent:adorno drops a point on code the diff does not touch
# outside DIFF: the planted findings of case.json (stdin) whose lines meet no hunk of the diff, as FILE:FIRST-LAST
outside() {
  awk -F '\t' -v diff="$1" 'BEGIN { while ((getline l < diff) > 0) {
                      if (l ~ /^\+\+\+ b\//) f = substr(l, 7)
                      else if (l ~ /^@@ /) { split(l, w, " "); n = split(substr(w[3], 2), r, ",")
                                             s = r[1] + 0; c = (n > 1 ? r[2] + 0 : 1); h[++k] = f "\t" s "\t" s + c - 1 } } }
                    { inside = 0
                      for (i = 1; i <= k; i++) { split(h[i], x, "\t"); if (x[1] == $1 && $2 <= x[3] && $3 >= x[2]) inside = 1 }
                      if (!inside) printf "%s:%s-%s ", $1, $2, $3 }'
}
got="$(jq -r '.planted[] | select(.lines != null) | "\(.file)\t\(.lines[0])\t\(.lines[1])"' "$B/cases/adorno-false-positives/case.json" \
  | outside "$B/cases/adorno-false-positives/change.diff")"
if [ "$got" = "server/services/orders.ts:22-22 " ]; then
  ok "adorno-false-positives: one planted finding lies outside the change's hunks, the others inside"
else
  ko "adorno-false-positives: one planted finding lies outside the change's hunks, the others inside" "outside: '$got'"
fi
if [ "$adorno_cases" -ge 2 ]; then ok "cases of kind adorno are there ($adorno_cases)"; else ko "cases of kind adorno are there" "$adorno_cases"; fi
if python3 - "$B/cases" 2>"$TMP/err" <<'PY'
import json, pathlib, re, sys
for path in sorted(pathlib.Path(sys.argv[1]).glob("*/case.json")):
    case = json.loads(path.read_text())
    for entry in case["findings"] + case.get("extras", []) + case.get("planted", []):
        for keyword in entry["keywords"]:
            re.compile(keyword)  # the scoring searches them as regular expressions
PY
then ok "every keyword is a valid regular expression"; else ko "every keyword is a valid regular expression" "$(tail -c 300 "$TMP/err")"; fi

echo "routing (public default rules from repos.yaml)"
REAL="$ROOT/dist/claude/.claude/skills/adorno-github/repos.json"
if [ -f "$REAL" ]; then
  # adorno/bare drops the `always` reviewers: docs-only then routes to no reviewer at all
  jq '.repos = {"adorno/bench": {}, "adorno/bare": {"areas": {"always": {"review": ["-agent:review:code", "-agent:review:ponytail"]}}}}' \
    "$REAL" >"$KH/registry.json"
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
  if grep -q "^# Reviewer benchmark: first" <<<"$out" && grep -q '^| `mongo-n-plus-one` | 100% | 100% | 1/1 | 1/1 (fix) |' <<<"$out"; then
    ok "and its report is printed"
  else
    ko "and its report is printed" "$(head -c 600 <<<"$out")"
  fi
  out="$(cat "$R/first/run.json")"
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

  expect_exit 0 "a case of kind adorno" -- "$B/run" --case adorno-false-positives --label fixed --results "$R"
  has_line() { if grep -qF -- "$2" <<<"$out"; then ok "$1"; else ko "$1" "no '$2' in: $(head -c 900 <<<"$out")"; fi; }
  has_line "its report gives agent:adorno its own section" "## agent:adorno on a fixed review"
  has_line "what it kept and what it dropped" "| dropped | 100% | 4/4 planted false findings left out |"
  calls
  expect_jq "starts agent:adorno alone" 'length == 1 and (.[0] | .[index("--agent") + 1] == "adorno:adorno")'
  D="$R/fixed/adorno-false-positives/1"
  out="$(cat "$D/review.json")"
  expect_jq "on the merged reviews the case brings" '.verdict == "block" and (.findings | length) == 6 and .invalid == [] and (.agents | length) == 6'
  out="$(cat "$D/run.json")"
  expect_jq "with no review missing or invalid" '.missing == [] and .invalid == [] and .verdict == "block"'
  if [ "$(find "$D/reviews" -name '*.json' | wc -l)" -eq 6 ] && [ -f "$D/review-final.json" ]; then
    ok "the reviews given and what agent:adorno wrote are kept"
  else
    ko "the reviews given and what agent:adorno wrote are kept" "$(find "$D" -type f | head -20)"
  fi

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

  # an agent plants a dangling link where its review goes, and gives a salvageable review in its message
  printf '%s' "$TMP/outside.json" >"$FK/tests.link"
  printf 'Here it is: {"agent":"agent:review:tests","verdict":"pass","findings":[]}\n' >"$FK/tests.message"
  expect_exit 1 "a link an agent plants in its run folder" -- "$B/run" --case docs-only --case clean-refactor --label planted --results "$R"
  if grep -q "^> \*\*Failed case runs\*\*.*clean-refactor #1" <<<"$out"; then ok "is named at the top of the report"; else ko "is named at the top of the report" "$(head -c 400 <<<"$out")"; fi
  if [ ! -e "$TMP/outside.json" ]; then ok "is never written through"; else ko "is never written through" "$(cat "$TMP/outside.json")"; fi
  out="$(cat "$R/planted/clean-refactor/1/run.json")"
  expect_jq "fails that case run, and names the link" '(.failed | type) == "string" and .links == [".agent-run/review/reviews/tests.json"]'
  if [ ! -e "$R/planted/clean-refactor/1/reviews" ] && [ ! -e "$R/planted/clean-refactor/1/review.json" ]; then
    ok "nothing of it is copied"
  else
    ko "nothing of it is copied" "$(find "$R/planted/clean-refactor/1" | head -20)"
  fi
  out="$(cat "$R/planted/run.json")"
  expect_jq "the run records it apart, and goes on with the other cases" \
    '.failed == [{"case": "clean-refactor", "n": 1, "links": [".agent-run/review/reviews/tests.json"]}] and (.runs | map(.case)) == ["docs-only"]'
  rm "$FK/tests.link" "$FK/tests.message"; calls

  expect_exit 0 "a tool that crashes on a reviewer" -- env FAKE_CLAUDE_FAIL=back "$B/run" --case clean-refactor --label crash --results "$R"
  D="$R/crash/clean-refactor/1"
  out="$(cat "$D/meta/back.json")"
  expect_jq "is an error, not a review: no cost, and run once more" \
    '.stop == "tool_failed" and .is_error and .cost_usd == null and .attempts == 2 and .delivered == "none"'
  if grep -q "fake-claude: back crashed" "$D/messages/back.md"; then ok "what the tool said is kept as its message"; else ko "what the tool said is kept as its message" "$(cat "$D/messages/back.md")"; fi
  out="$(cat "$D/run.json")"
  expect_jq "the review is reported missing" '.missing == ["agent:review:back"]'
  if [ -f "$D/meta/adorno.json" ]; then ok "and the run goes on to agent:adorno"; else ko "and the run goes on to agent:adorno"; fi
  calls

  expect_exit 0 "a tool that reports no cost" -- env FAKE_CLAUDE_COST=null "$B/run" --case docs-only --repeat 2 --budget-usd 0.05 --label free --results "$R"
  if grep -qF "| cost | – |" <<<"$out"; then ok "the report shows no cost"; else ko "the report shows no cost" "$(grep -F "| cost" <<<"$out")"; fi
  if grep -q "reports no cost: --budget-usd did not apply" "$TMP/err"; then ok "says the budget did not apply"; else ko "says the budget did not apply" "$(cat "$TMP/err")"; fi
  out="$(cat "$R/free/run.json")"
  expect_jq "and runs every repeat, with no cost recorded" '.cost_usd == null and .skipped == [] and (.runs | length) == 2 and all(.runs[]; .cost_usd == null)'
  calls

  expect_exit 0 "a budget" -- "$B/run" --case docs-only --repeat 3 --budget-usd 0.05 --label budget --results "$R"
  if grep -q "Incomplete run.*docs-only #2, docs-only #3" <<<"$out"; then ok "is named at the top of the report when it cut the run"; else ko "is named at the top of the report when it cut the run" "$(head -c 400 <<<"$out")"; fi
  out="$(cat "$R/budget/run.json")"
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
  expect_exit 0 "a budget on a case with more reviewers than --parallel" -- "$B/run" --case mongo-n-plus-one --parallel 3 --budget-usd 0.5 --label wide --results "$R"
  calls
  expect_jq "splits what is left over every reviewer's call, not over the slots" \
    '[.[] | select(.[index("--agent") + 1] != "adorno:adorno") | .[index("--max-budget-usd") + 1] | tonumber] | length == 6 and add <= 0.5'
  expect_exit 0 "a budget on a routing that picks no reviewer" -- "$B/run" --repo adorno/bare --case docs-only --budget-usd 0.05 --label bare --results "$R"
  calls
  expect_jq "goes straight to agent:adorno, with the whole budget" \
    'length == 1 and (.[0] | .[index("--agent") + 1] == "adorno:adorno" and (.[index("--max-budget-usd") + 1] | tonumber) == 0.05)'

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

echo "scoring (fixed results)"
# two cases with one expected finding each (anchored on lines, and on the file as a whole), and one without defect
SC="$TMP/scases"; mkdir -p "$SC/defect" "$SC/whole" "$SC/clean"
ROUTING='"routing":{"areas":["back"],"review":["agent:review:code","agent:review:mongodb"]}'
printf '{"title":"t","description":"d","rationale":"r",%s,"verdict":["fix"],"findings":[{"file":"a.ts","lines":[10,12],"category":"n-plus-one","severity":["major"],"keywords":["n\\\\+1","per item"],"reviewer":"agent:review:mongodb"}]}' "$ROUTING" >"$SC/defect/case.json"
printf '{"title":"t","description":"d","rationale":"r",%s,"verdict":["pass","fix"],"findings":[{"file":"README.md","lines":null,"category":"stale-doc","severity":["minor","major"],"keywords":["outdated"],"reviewer":"agent:review:code"}]}' "$ROUTING" >"$SC/whole/case.json"
printf '{"title":"t","description":"d","rationale":"r",%s,"verdict":["pass"],"findings":[]}' "$ROUTING" >"$SC/clean/case.json"
# finding FILE LINE SEVERITY TITLE [AGENT] [FIX]: one finding of a merged review (LINE may be null)
finding() {
  printf '{"severity":"%s","file":"%s","line":%s,"title":"%s","detail":"","fix":"%s","agents":["agent:review:%s"]}' "$3" "$1" "$2" "$4" "${6:-}" "${5:-mongodb}"
}
# review VERDICT [FINDING…]: a merged review, as review-merge prints it
review() { local verdict="$1"; shift; local IFS=,; printf '{"verdict":"%s","counts":{},"findings":[%s],"agents":[],"invalid":[]}' "$verdict" "$*"; }
# result LABEL CASE N REVIEW [FINAL] [ADORNO_ERROR]: what bench/run leaves for one case run (one agent, 0.5 USD, 1000
# tokens in, 50 out); ADORNO_ERROR: agent:adorno also wrote its notes, and its meta ended with false (success), true
# (an error, its stop success, as an API error leaves it) or turns (no error, but cut by the turns) (no cost, no tokens,
# so the sums above stay those of the one agent)
result() {
  local d="$R/$1/$2/$3"; mkdir -p "$d/meta"
  printf '%s' "$4" >"$d/review.json"
  [ -z "${5:-}" ] || printf '%s' "$5" >"$d/review-final.json"
  if [ -n "${6:-}" ]; then
    local error=false stop=error_max_turns
    [ "$6" = turns ] || stop=success
    [ "$6" != true ] || error=true
    printf 'Nothing worth posting.\n' >"$d/review-notes.md"
    printf '{"agent":"agent:adorno","attempts":1,"delivered":"file","is_error":%s,"stop":"%s","models":["m-1"],"cost_usd":null,"duration_ms":0,"turns":1,"denied":0,"tokens":{"input":0,"cache_read":0,"cache_write":0,"output":0}}' "$error" "$stop" >"$d/meta/adorno.json"
  fi
  printf '{"case":"%s","diff_base":"0","routing_ok":true,"missing":[],"invalid":[],"verdict":"-","budget_exhausted":false,"cost_usd":0.5,"duration_ms":60000}' "$2" >"$d/run.json"
  printf '{"agent":"agent:review:mongodb","attempts":1,"delivered":"file","is_error":false,"stop":"success","models":["m-1"],"cost_usd":0.5,"duration_ms":60000,"turns":1,"denied":0,"tokens":{"input":100,"cache_read":800,"cache_write":100,"output":50}}' >"$d/meta/mongodb.json"
}
# close LABEL "CASE:N …": the run.json of the whole run
close() {
  jq -n --arg label "$1" --arg runs "$2" '{label: $label, tool: "claude", tool_version: "0", model: "m-1", repo: "adorno/bench", repeat: 1, cases: [], prompts: {sha: "abcdef0123456", dirty: false}, started_at: "2026-01-01T00:00:00+00:00", budget_usd: null, cost_usd: 1, skipped: [], runs: ($runs | split(" ") | map(split(":") | {case: .[0], n: (.[1] | tonumber), cost_usd: 0.5}))}' >"$R/$1/run.json"
}
score() { expect_exit 0 "$2" -- "$B/score" --label "$1" --results "$R" --cases "${3:-$SC}"; }
FOUND="$(finding a.ts 11 major 'N+1 in the loop')"
STALE="$(finding README.md 40 minor 'Outdated setup section' code)"
KEPT='{"body":"One point.","comments":[{"path":"a.ts","line":11,"side":"RIGHT","body":"issue (non-blocking): N+1, one query per item."}]}'

result perfect defect 1 "$(review fix "$FOUND")" "$KEPT"
result perfect whole 1 "$(review pass "$STALE")"
result perfect clean 1 "$(review pass)"
close perfect "defect:1 whole:1 clean:1"
score perfect "a perfect run"
expect_jq "everything found, nothing else, right severities and verdicts" \
  '.overall | .recall == {"mean": 1, "min": 1, "max": 1} and .precision.mean == 1 and .found == 2 and .expected == 2 and .severity_ok == 2 and .attribution_ok == 2 and .verdict_ok == 3 and .runs == 3 and .routing_ok == 3 and .invalid_reviews == 0 and .ungraded == 0'
expect_jq "the clean case raises no alarm" '.overall.clean == {"runs": 1, "false_alarms": 0, "verdict_ok": 1} and .cases.clean.runs[0].recall == null and .cases.clean.runs[0].precision == null'
expect_jq "cost, tokens and time are summed, per run and per agent" \
  '(.overall | .cost_usd == 1.5 and .tokens_in == 3000 and .tokens_out == 150 and .duration_ms == 180000) and (.agents["agent:review:mongodb"] | .runs == 3 and .calls == 3 and .models == ["m-1"] and .cost_usd == 1.5 and .delivered == {"file": 3, "salvaged": 0, "none": 0})'
expect_jq "what agent:adorno kept is scored the same way, from its inline comments and badges" \
  '(.cases.defect.runs[0].final | .state == "ok" and .found == 1 and .recall == 1 and .severity_ok == 1 and .verdict == "fix" and .verdict_ok) and (.cases.whole.runs[0].final | .state == "absent" and .found == 0 and .verdict == null and .verdict_ok == null)'
if [ -f "$R/perfect/score.json" ]; then ok "score.json is written next to the results"; else ko "score.json is written next to the results"; fi

result missed defect 1 "$(review pass)"
result missed whole 1 "$(review pass "$STALE")"
result missed clean 1 "$(review pass)"
close missed "defect:1 whole:1 clean:1"
score missed "a missed finding"
expect_jq "lowers the recall, and the verdict is wrong with it" \
  '.cases.defect.runs[0].recall == 0 and (.cases.defect.runs[0].verdict_ok | not) and .overall.recall.mean == 0.5 and .overall.verdict_ok == 2'

result extra defect 1 "$(review fix "$FOUND" "$(finding b.ts 3 minor 'Rename this helper' code)")"
close extra "defect:1"
score extra "a finding the case does not plan"
expect_jq "counts against precision and is listed to grade" \
  '.cases.defect.runs[0] == (.cases.defect.runs[0] | .recall = 1 | .precision = 0.5 | .ungraded = 1) and (.ungraded | length == 1 and .[0].case == "defect" and .[0].n == 1 and .[0].file == "b.ts" and .[0].agents == ["agent:review:code"])'
for grade in true false; do
  mkdir -p "$TMP/graded-$grade/defect"
  jq --argjson valid "$grade" '.extras = [{"file": "b.ts", "lines": null, "keywords": ["rename"], "valid": $valid, "note": "graded by the owner"}]' "$SC/defect/case.json" >"$TMP/graded-$grade/defect/case.json"
done
score extra "graded valid in case.json" "$TMP/graded-true"
expect_jq "it no longer weighs on precision" '.cases.defect.runs[0] | .precision == 1 and .valid_extras == 1 and .ungraded == 0'
score extra "graded invalid in case.json" "$TMP/graded-false"
expect_jq "it is a false positive" '(.cases.defect.runs[0] | .precision == 0.5 and .invalid_extras == 1 and .ungraded == 0) and .ungraded == []'

result severity defect 1 "$(review block "$(finding a.ts 11 blocker 'N+1 in the loop')")"
close severity "defect:1"
score severity "a wrong severity"
expect_jq "is found, but neither its severity nor the verdict is accepted" '.cases.defect.runs[0] | .recall == 1 and .severity_ok == 0 and (.verdict_ok | not)'

result alarm clean 1 "$(review pass "$(finding c.ts 1 minor 'Could be shorter' code)")"
result alarm clean 2 "$(review fix "$(finding c.ts 1 major 'Wrong on empty input' code)")"
close alarm "clean:1 clean:2"
score alarm "findings on a clean case"
expect_jq "are false alarms, and a major one breaks the verdict" \
  '.overall.clean == {"runs": 2, "false_alarms": 2, "verdict_ok": 1} and .cases.clean.runs[0].false_alarms == 1 and .cases.clean.runs[0].precision == 0'

result verdict defect 1 "$(review pass "$FOUND")"
close verdict "defect:1"
score verdict "a verdict the case does not accept"
expect_jq "is a mismatch even when the finding is found" '.cases.defect.runs[0] | .recall == 1 and (.verdict_ok | not) and .verdict == "pass"'

# the matching rule, on its edges: expected on a.ts lines 10-12, keywords `n\+1` and `per item`
edge() {  # edge NAME FOUND(0|1) FINDING [CASE]
  result "edge-$1" "${4:-defect}" 1 "$(review fix "$3")"; close "edge-$1" "${4:-defect}:1"
  out="$("$B/score" --label "edge-$1" --results "$R" --cases "$SC" 2>"$TMP/err")"
  expect_jq "matching: $1" ".overall.found == $2"
}
edge "3 lines after the range" 1 "$(finding a.ts 15 major 'N+1 here')"
edge "3 lines before the range" 1 "$(finding a.ts 7 major 'N+1 here')"
edge "4 lines after is too far" 0 "$(finding a.ts 16 major 'N+1 here')"
edge "4 lines before is too far" 0 "$(finding a.ts 6 major 'N+1 here')"
edge "another file" 0 "$(finding b.ts 11 major 'N+1 here')"
edge "no keyword" 0 "$(finding a.ts 11 major 'Slow loop')"
edge "the keyword in another case" 1 "$(finding a.ts 11 major 'One query PER ITEM')"
edge "the keyword in the fix only" 1 "$(finding a.ts 11 major 'Slow loop' mongodb 'avoid the n+1')"
edge "no line on a finding expected on lines" 0 "$(finding a.ts null major 'N+1 here')"
edge "a file-level finding matches on any line" 1 "$(finding README.md 3 minor 'Outdated section' code)" whole
edge "a file-level finding matches without a line" 1 "$(finding README.md null minor 'Outdated section' code)" whole

result twice defect 1 "$(review block "$FOUND" "$(finding a.ts 12 blocker 'One query per item' code)")"
close twice "defect:1"
score twice "two findings on the same expected one"
expect_jq "count once for recall, the other is a duplicate, and the highest severity is the one judged" \
  '.cases.defect.runs[0] | .found == 1 and .matched == 2 and .duplicates == 1 and .precision == 1 and .ungraded == 0 and .severity_ok == 0 and .attribution_ok == 1'
result other defect 1 "$(review fix "$(finding a.ts 11 major 'N+1 in the loop' code)")"
close other "defect:1"
score other "a finding raised by another reviewer than the expected one"
expect_jq "is found, not attributed" '.cases.defect.runs[0] | .found == 1 and .attribution_ok == 0'

result broken defect 1 "$(review fix "$FOUND")"
jq '.invalid = ["back.json"] | .missing = ["agent:review:tests"] | .routing_ok = false' "$R/broken/defect/1/run.json" >"$TMP/run.json"; cp "$TMP/run.json" "$R/broken/defect/1/run.json"
close broken "defect:1"
score broken "invalid and missing reviews, a routing that differs"
expect_jq "are counted" '.overall | .invalid_reviews == 2 and .routing_ok == 0'

result repeats defect 1 "$(review fix "$FOUND")"
result repeats defect 2 "$(review pass)"
result repeats clean 1 "$(review pass)"
result repeats clean 2 "$(review pass)"
close repeats "defect:1 clean:1 defect:2 clean:2"
score repeats "several repeats"
expect_jq "give the mean and the spread of recall and precision" \
  '.overall.recall == {"mean": 0.5, "min": 0, "max": 1} and .overall.precision == {"mean": 1, "min": 1, "max": 1} and .cases.defect.summary.runs == 2 and .cases.defect.summary.verdict_ok == 1 and (.cases.defect.runs | map(.n)) == [1, 2]'

result blocking defect 1 "$(review fix "$FOUND")" '{"body":"","comments":[{"path":"a.ts","line":11,"body":"issue (blocking): N+1, one query per item."},{"path":"z.ts","line":2,"body":"nitpick (non-blocking): naming."}]}'
close blocking "defect:1"
score blocking "a final review harsher than the case"
expect_jq "is scored on its own: found, wrong severity, wrong verdict, one comment to grade" \
  '.cases.defect.runs[0].final | .found == 1 and .severity_ok == 0 and .verdict == "block" and (.verdict_ok | not) and .reported == 2 and .ungraded == 1 and .precision == 0.5'

# agent:adorno's pass: readable (ok), unreadable or with a comment that is not an object (invalid), never written
# (absent), its notes and nothing else (none)
result final-states defect 1 "$(review fix "$FOUND")" "$KEPT"
result final-states defect 2 "$(review fix "$FOUND")" '{oops' false
result final-states whole 1 "$(review pass "$STALE")" '{"body":"","comments":["x"]}'
result final-states clean 1 "$(review pass)"
result final-states whole 2 "$(review pass "$STALE")" "" false
close final-states "defect:1 whole:1 clean:1 defect:2 whole:2"
score final-states "agent:adorno passes that are unreadable, absent or with nothing to post"
expect_jq "are recorded as such, with no verdict" \
  '(.cases.defect.runs[0].final | .state == "ok" and .verdict == "fix" and .verdict_ok) and ([.cases.defect.runs[1].final, .cases.whole.runs[0].final] | all(.state == "invalid" and .verdict == null and .verdict_ok == null)) and (.cases.clean.runs[0].final | .state == "absent" and .verdict == null and .verdict_ok == null)'
expect_jq "an invalid final review next to the notes stays invalid" '.cases.defect.runs[1].final.state == "invalid"'
expect_jq "notes and no final review on a review case: nothing to post, verdict pass" \
  '.cases.whole.runs[1].final | .state == "none" and .verdict == "pass" and .verdict_ok and .reported == 0 and .found == 0'
expect_jq "and the measures after agent:adorno pool the readable passes only, nothing to post included" \
  '.overall.final | .runs == 2 and .invalid == 2 and .absent == 1 and .none == 1 and .recall == {"mean": 0.5, "min": 0, "max": 1} and .precision.mean == 1 and .found == 1 and .verdict_ok == 2'
# a pass cut by the budget or the turns may have written its notes: only a pass that ended well has nothing to post
result cut whole 1 "$(review pass "$STALE")" "" true
result cut whole 2 "$(review pass "$STALE")"; printf 'Half a report.\n' >"$R/cut/whole/2/review-notes.md"
result cut whole 3 "$(review pass "$STALE")" "" turns
close cut "whole:1 whole:2 whole:3"
score cut "notes from a pass that ended in error, or with no agent:adorno meta"
expect_jq "are absent, not nothing to post" \
  '([.cases.whole.runs[].final] | all(.state == "absent" and .verdict == null)) and (.overall.final | .runs == 0 and .none == 0 and .absent == 3)'

# cases of kind adorno: the true finding of `defect`, planted false findings on a.ts lines 20 and 30
mkdir -p "$SC/fixed" "$SC/fixed-clean"
PLANT_T='{"file":"a.ts","lines":[20,20],"keywords":["tenant"],"why":"w"}' PLANT_P='{"file":"a.ts","lines":[30,30],"keywords":["projection"],"why":"w"}'
jq --argjson t "$PLANT_T" --argjson p "$PLANT_P" '.kind = "adorno" | .planted = [$t, $p]' "$SC/defect/case.json" >"$SC/fixed/case.json"
jq --argjson t "$PLANT_T" '.kind = "adorno" | .planted = [$t]' "$SC/clean/case.json" >"$SC/fixed-clean/case.json"
TENANT="$(finding a.ts 20 blocker 'Not scoped to the tenant' back)"
PROJ="$(finding a.ts 30 major 'No projection' perf-back)"
N1='{"path":"a.ts","line":11,"body":"issue (non-blocking): N+1, one query per item."}'
POST_T='{"path":"a.ts","line":20,"body":"issue (blocking): not scoped to the tenant."}'
POST_P='{"path":"a.ts","line":30,"body":"issue (non-blocking): no projection."}'
# adorno RUN-LABEL FINAL-COMMENTS-OF-fixed: fixed, fixed-clean (notes, nothing posted), fixed #2 (nothing written),
# fixed #3 (an unreadable final review) and the review case defect
adorno_run() {
  result "$1" fixed 1 "$(review block "$FOUND" "$TENANT" "$PROJ")" "{\"body\":\"\",\"comments\":[$2]}"
  result "$1" fixed-clean 1 "$(review fix "$TENANT")" "" false
  result "$1" fixed 2 "$(review block "$FOUND" "$TENANT" "$PROJ")"
  result "$1" fixed 3 "$(review block "$FOUND" "$TENANT" "$PROJ")" '{oops'
  result "$1" defect 1 "$(review fix "$FOUND")" "$KEPT"
  close "$1" "fixed:1 fixed-clean:1 defect:1 fixed:2 fixed:3"
}
adorno_run adorno "$N1,$POST_T"
score adorno "cases of kind adorno"
expect_jq "are kept apart from the reviewers' measures" \
  '.overall.runs == 1 and .overall.recall.mean == 1 and .overall.precision.mean == 1 and .adorno.runs == 4 and .cases.fixed.kind == "adorno" and .cases.defect.kind == "review"'
expect_jq "measure what agent:adorno kept and what it dropped, over its readable passes" \
  '.adorno | .recall == {"mean": 1, "min": 1, "max": 1} and .found == 1 and .expected == 1 and .planted == 3 and .planted_kept == 1 and .dropped == {"mean": 0.6667, "min": 0.6667, "max": 0.6667} and .precision.mean == 0.5 and .verdict_ok == 1 and .none == 1 and .reviewed == 2'
expect_jq "and count an absent and an unreadable pass apart" '.adorno | .runs == 4 and .absent == 1 and .invalid == 1'
expect_jq "a planted finding it posts is classed planted, never to grade" \
  '(.cases.fixed.runs[0].final.findings | map(.class)) == ["matched", "planted"] and .ungraded == [] and .cases.fixed.summary.dropped.mean == 0.5'
expect_jq "notes and no final review: nothing worth posting, a readable pass with the verdict pass" \
  '.cases["fixed-clean"].runs[0].final | .state == "none" and .verdict == "pass" and .verdict_ok and .reported == 0'
adorno_run adorno-worse "$N1,$POST_T,$POST_P"
score adorno-worse "agent:adorno keeping every planted finding"
expect_jq "drops less" '.cases.fixed.summary.dropped.mean == 0 and .adorno.dropped.mean == 0.3333'
adorno_run adorno-extra "$N1,{\"path\":\"z.ts\",\"line\":2,\"body\":\"nitpick (non-blocking): naming.\"}"
score adorno-extra "a comment of agent:adorno that matches nothing"
expect_jq "is listed to grade, as agent:adorno's" '.ungraded | length == 1 and .[0].case == "fixed" and .[0].file == "z.ts" and .[0].agents == ["agent:adorno"]'

# the real cases of kind adorno, scored with the scorer's own rule: a planted claim counts as kept even when the same
# comment also matches the true finding, and a true comment that names what the planted claims deny is not one
AF=adorno-false-positives
posted() { printf '{"body":"","comments":[{"path":"server/services/orders.ts","line":%s,"side":"RIGHT","body":"%s"}]}' "$1" "$2"; }
result real-loop "$AF" 1 "$(review block)" "$(posted 38 'issue (blocking): the findOne inside the loop is not scoped to the tenant.')"
close real-loop "$AF:1"
score real-loop "a planted claim worded around the loop" "$B/cases"
expect_jq "counts as a planted finding kept" ".cases[\"$AF\"].runs[0].final | .planted_kept == 1 and .found == 1"
result real-n1 "$AF" 1 "$(review block)" "$(posted 36 'issue (non-blocking): this awaits a findOne for each order of the page. Collect the customerIds and run one $in query with the same projection, null for a deleted customer.')"
close real-n1 "$AF:1"
score real-n1 "a true N+1 comment that names the projection and the deleted customer" "$B/cases"
expect_jq "is the true finding, and keeps no planted one" ".cases[\"$AF\"].runs[0].final | .found == 1 and .matched == 1 and .planted_kept == 0"
result real-n1-keep "$AF" 1 "$(review block)" "$(posted 38 'issue (non-blocking): one $in query keeping accountId in the filter so it never returns another account'"'"'s customer; keep the projection, do not fetch the full customer document.')"
close real-n1-keep "$AF:1"
score real-n1-keep "a true N+1 comment that says to keep the tenant key and the projection" "$B/cases"
expect_jq "is the true finding, and keeps no planted one" ".cases[\"$AF\"].runs[0].final | .found == 1 and .matched == 1 and .planted_kept == 0"
result real-n1-test "$AF" 1 "$(review block)" "$(posted 39 'issue (non-blocking): N+1: batch the findOne calls with $in. No test change needed: the null case is covered.')"
close real-n1-test "$AF:1"
score real-n1-test "a true N+1 comment that says the test needs no change" "$B/cases"
expect_jq "is the true finding, and keeps no planted one" ".cases[\"$AF\"].runs[0].final | .found == 1 and .matched == 1 and .planted_kept == 0"
# every finding of the given reviews posted verbatim: each true one is found, each planted one is kept
BADGE='{"blocker": "issue (blocking)", "major": "issue (non-blocking)", "minor": "suggestion (non-blocking)", "question": "question (non-blocking)"}'
for dir in "$B"/cases/*/; do
  dir="${dir%/}"; id="$(basename "$dir")"
  [ "$(jq -r '.kind // "review"' "$dir/case.json")" = adorno ] || continue
  merged="$("$ROOT/src/skills/adorno-github/scripts/review-merge" "$dir/reviews")"
  result "verbatim-$id" "$id" 1 "$merged" "$(jq -c --argjson badge "$BADGE" '{body: "", comments: [.findings[] | {path: .file, line, side: "RIGHT", body: "\($badge[.severity]): \(.title) \(.detail // "") \(.fix // "")"}]}' <<<"$merged")"
  close "verbatim-$id" "$id:1"
  score "verbatim-$id" "$id: every given finding posted verbatim" "$B/cases"
  expect_jq "$id: each true finding is found, each planted one is kept and classed planted, none is to grade" \
    ".cases[\"$id\"].runs[0].final | .found == .expected and .planted_kept == .planted and .planted_comments == .planted and .matched + .planted_comments == .reported and .ungraded == 0"
  [ "$id" != "$AF" ] || expect_jq "$id: the inflated N+1 counts as a duplicate of the true one" ".cases[\"$id\"].runs[0].final.duplicates == 1"
done

expect_exit 2 "score: unknown run" -- "$B/score" --label nope --results "$R" --cases "$SC"
expect_exit 2 "score: a case the cases folder does not have" -- "$B/score" --label perfect --results "$R" --cases "$TMP/graded-true"
expect_exit 2 "score: no label" -- "$B/score" --results "$R"

echo "report"
BL="$TMP/baselines"
report() { local name="$1"; shift; expect_exit 0 "$name" -- "$B/report" --results "$R" --cases "$SC" --baselines "$BL" "$@"; }
has() { if grep -qF -- "$2" <<<"$out"; then ok "$1"; else ko "$1" "no '$2' in: $(head -c 700 <<<"$out")"; fi; }  # has NAME TEXT
report "the report of a run" --label perfect
has "names the run, the tool, the model and the prompts" "claude (0), model: m-1, prompts abcdef0, 3 cases, 1 repeat(s)"
has "gives the measures overall" "| recall | 100% | 2/2 expected findings found |"
has "the verdicts" "| verdict | 3/3 | merged verdict accepted by the case |"
has "the cost and the tokens" "| cost | \$1.50 | 3k tokens in, 150 out, 3.0 min of agent time |"
has "one line per case" '| `defect` | 100% | 100% | 1/1 | 1/1 (fix) | 0 | 100% | $0.50 |'
has "one line per agent" '| `agent:review:mongodb` | 3 | 3 | m-1 | 3k | 150 | $1.50 | 3.0 min | 0 salvaged, 0 missing |'
if grep -q "Findings to grade\|## Against" <<<"$out"; then ko "no section without content"; else ok "no section without content"; fi
if [ -f "$R/perfect/report.md" ] && jq -e '.score.label == "perfect" and .comparison == null' "$R/perfect/report.json" >/dev/null; then
  ok "report.md and report.json are written next to the results"
else
  ko "report.md and report.json are written next to the results"
fi
report "a run with findings to grade" --label extra
has "lists them with where to grade them" '- `defect` #1 🟡 `b.ts:3` Rename this helper (code)'
has "and says how" 'case.json` › `extras`'
report "a run whose agent:adorno pass broke" --label final-states
has "counts the passes left out after agent:adorno" "| after agent:adorno | recall 50% (worst 0%, best 100%), precision 100% | 1 inline comments, verdict 2/2, 1 with nothing to post, 1 absent, 2 invalid |"
report "a run over several repeats" --label repeats
has "shows the mean, the worst and the best run" "| recall | 50% (worst 0%, best 100%) |"

report "a comparison with another run" --label missed --against perfect
has "says what regressed, and by how much" '- **regressed** `defect`: recall -100 pts, precision –, severity –, verdict -100 pts'
has "what did not move" '- same: `clean`, `whole`'
has "and the overall difference" "| recall | 50% | 1/2 expected findings found | -50 pts |"
out="$(cat "$R/missed/report.json")"
expect_jq "the same in report.json" \
  '.comparison | .against == "perfect" and .overall.recall == -50 and .overall.status == "regressed" and (.cases | map(select(.case == "defect"))[0] | .status == "regressed" and .recall == -100 and .cost_usd == 0)'
report "the other way round" --label perfect --against missed
has "says what improved" '- **improved** `defect`: recall +100 pts'
report "a comparison between runs that do not hold the same cases" --label extra --against perfect
has "names the cases only one of them has" '- only in perfect: `clean`, `whole`'

report "a run saved as a baseline" --label perfect --save-baseline reference
out="$(cat "$BL/reference.json")"
expect_jq "keeps the scores under its own name, and no text written by a model" \
  '.label == "reference" and .overall.recall.mean == 1 and (has("ungraded") | not) and ([.. | objects | select(has("title") or has("findings"))] == [])'
report "a comparison with a baseline" --label missed --against reference
has "reads it like a run" '- **regressed** `defect`: recall -100 pts'
report "a run with cases of kind adorno" --label adorno
has "gives agent:adorno its own section" "## agent:adorno on a fixed review"
has "what it kept" "| kept | 100% | 1/1 true findings kept |"
has "what it dropped" "| dropped | 67% | 2/3 planted false findings left out |"
has "the verdict over every pass, and the passes left out" "| verdict | 1/4 | 1 with nothing to post, 1 absent, 1 invalid |"
has "one line per case of kind adorno" '| `fixed` | 100% | 50% | 50% | 0/3 (block, –) | 0 | $1.50 |'
if [ "$(grep -c '`fixed-clean`' <<<"$out")" = 1 ]; then ok "and leaves them out of the reviewers' table"; else ko "and leaves them out of the reviewers' table" "$(grep '`fixed-clean`' <<<"$out")"; fi
report "a comparison of agent:adorno passes" --label adorno-worse --against adorno
has "says what it dropped less" '- **regressed** `fixed`: recall =, precision -17 pts, severity =, verdict =, dropped -50 pts'
has "and the overall difference" "| dropped | 33% | 1/3 planted false findings left out | -33 pts |"
report "a run with cases of kind adorno saved as a baseline" --label adorno --save-baseline adorno-reference
out="$(cat "$BL/adorno-reference.json")"
expect_jq "keeps no text written by a model either" '.adorno.dropped.mean == 0.6667 and ([.. | objects | select(has("title") or has("findings"))] == [])'

expect_exit 2 "a baseline is never overwritten" -- "$B/report" --results "$R" --cases "$SC" --baselines "$BL" --label missed --save-baseline reference
expect_exit 2 "report: nothing to compare with" -- "$B/report" --results "$R" --cases "$SC" --baselines "$BL" --label missed --against nope
expect_exit 2 "report: unknown run" -- "$B/report" --results "$R" --cases "$SC" --baselines "$BL" --label nope

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
