#!/usr/bin/env bash
# Tests for src/skills/adorno-learn/scripts. Usage: tests/adorno-learn.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/src/skills/adorno-learn/scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err" </dev/null)"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(cat "$TMP/err")"; fi
}
expect_jq() { if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $out"; fi; }
note() { "$S/learn-note" --kind code --target engineering-types.md --observation "o" --proposal "p" "$@"; }

echo "learn"
expect_exit 2 "evidence required" -- note --key batch-reads
expect_exit 2 "bad kind" -- "$S/learn-note" --key ab-c --kind food --target x --observation o --proposal p --evidence e
expect_exit 0 "first sighting" -- note --key batch-reads --evidence pr/1
expect_jq "pending, seen once" '.seen == 1 and .status == "pending" and .strength == "inferred"'
expect_exit 0 "not ready after one inferred sighting" -- "$S/learn-list" --ready
expect_jq "ready empty" '. == []'
expect_exit 0 "second sighting" -- note --key batch-reads --evidence pr/2 --evidence pr/1
expect_jq "merged, evidence unique" '.seen == 2 and .evidence == ["pr/1", "pr/2"]'
expect_exit 0 "explicit statement" -- "$S/learn-note" --key no-any --kind code --target engineering-types.md \
  --observation "said: never any" --proposal "No any, ever." --evidence slack/1 --strength explicit
expect_exit 0 "ready list" -- "$S/learn-list" --ready
expect_jq "explicit first, then seen twice" '[.[].key] == ["no-any", "batch-reads"]'
expect_exit 0 "reject" -- "$S/learn-decide" no-any rejected "too strict"
expect_exit 0 "noted again after rejection" -- "$S/learn-note" --key no-any --kind code --target t --observation o \
  --proposal p --evidence slack/2 --strength explicit
expect_jq "stays rejected" '.status == "rejected"'
expect_exit 0 "pending list" -- "$S/learn-list"
expect_jq "rejected not proposed" '[.[].key] == ["batch-reads"]'
expect_exit 0 "all" -- "$S/learn-list" --all
expect_jq "all keys" '(map(.key) | sort) == ["batch-reads", "no-any"]'
expect_exit 3 "unknown key" -- "$S/learn-decide" nope accepted
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
