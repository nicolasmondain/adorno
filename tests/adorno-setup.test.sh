#!/usr/bin/env bash
# Tests for src/skills/adorno-setup/scripts. No network. Usage: tests/adorno-setup.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/src/skills/adorno-setup/scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"; ln -s "$ROOT/tests/fake-gh" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" HOME="$TMP/home" FAKE_FIX="$ROOT/tests/fixtures"
unset ADORNO_SOURCE ADORNO_LOCAL
pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err" </dev/null)"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(cat "$TMP/err")"; fi
}
expect_jq() { if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $out"; fi; }

echo "adorno-source"
expect_exit 3 "nothing installed: not found" -- "$S/adorno-source"
# a cloned project ships its own record pointing at a fake kit: never trusted
P="$TMP/evil"; mkdir -p "$P/.adorno" "$P/kit/bin"; printf '#!/bin/sh\n' >"$P/kit/bin/kit"; chmod +x "$P/kit/bin/kit"
printf 'name: adorno\n' >"$P/kit/kit.yaml"
printf '{"source": "%s"}' "$P/kit" >"$P/.adorno/installed.json"
expect_exit 3 "a record inside a project is ignored" -- sh -c "cd '$P' && '$S/adorno-source'"
mkdir -p "$HOME/.adorno"; printf '{"source": "%s"}' "$ROOT" >"$HOME/.adorno/installed.json"
expect_exit 0 "the global install record is used" -- "$S/adorno-source"
expect_jq "source and layer" ".source == \"$ROOT\" and (.local | endswith(\"/local\"))"
printf '{"source": "%s"}' "$TMP" >"$HOME/.adorno/installed.json"
expect_exit 3 "a source that is not adorno is refused" -- "$S/adorno-source"
ADORNO_SOURCE="$ROOT" expect_exit 0 "ADORNO_SOURCE wins" -- "$S/adorno-source"

echo "voice-samples"
expect_exit 0 "samples" -- "$S/voice-samples" 5
expect_jq "only the owner's own words" \
  '.login == "octocat" and ([.reviewComments[] | select(.kind == "inline") | .url] == ["c1", "c3"]) and (.prDescriptions | length) == 1'
expect_exit 2 "limit must be a number" -- "$S/voice-samples" many

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
