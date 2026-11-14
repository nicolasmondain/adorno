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

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
