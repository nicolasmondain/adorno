#!/usr/bin/env bash
# Tests for adorno-inputs/scripts/input-refs: what a request points to. No network. Usage: tests/adorno-inputs.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/src/skills/adorno-inputs/scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err" </dev/null)"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(tail -c 300 "$TMP/err")"; fi
}
expect_jq() { if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $(head -c 400 <<<"$out")"; fi; }

printf '# Plan\n1. API\n2. UI\n' >"$TMP/plan.md"
SLACK="https://acme.slack.com/archives/C0123ABCD/p1730800000000100?thread_ts=1730799000.000200&cid=C0123ABCD"
NOTION="https://www.notion.so/acme/Export-CSV-1a2b3c4d5e6f40718293a4b5c6d7e8f9?pvs=4"

echo "input-refs"
expect_exit 0 "a request with every kind of source" -- "$S/input-refs" \
  "Export campaign CSV on acme/app, decided in $SLACK, detailed in $NOTION. See acme/app#42, https://github.com/acme/app/pull/7 and $TMP/plan.md."
expect_jq "kinds found" '.kinds == ["file", "github-pr", "github-ref", "notion", "slack"]'
expect_jq "Slack: channel, message and thread timestamps" \
  '.refs[] | select(.kind == "slack") | .workspace == "acme" and .channel == "C0123ABCD" and .ts == "1730800000.000100" and .thread_ts == "1730799000.000200"'
expect_jq "Notion: dashed page id" '.refs[] | select(.kind == "notion") | .page_id == "1a2b3c4d-5e6f-4071-8293-a4b5c6d7e8f9"'
expect_jq "GitHub: PR and short reference" \
  '([.refs[] | select(.kind == "github-pr")][0] | .repo == "acme/app" and .number == 7) and ([.refs[] | select(.kind == "github-ref")][0].number == 42)'
expect_jq "an existing plan file" '.refs[] | select(.kind == "file") | .path | endswith("/plan.md")'
expect_jq "the text keeps the request, without links" '(.text | test("Export campaign CSV")) and (.text | test("https://") | not)'

expect_exit 0 "a Slack message outside a thread" -- "$S/input-refs" "https://acme.slack.com/archives/C9/p1730800000000100"
expect_jq "its own timestamp is the thread" '.refs[0].ts == "1730800000.000100" and .refs[0].thread_ts == "1730800000.000100"'
expect_exit 0 "a Notion peek link" -- "$S/input-refs" "https://www.notion.so/acme/db?v=1&p=0123456789abcdef0123456789abcdef&pm=s"
expect_jq "the peeked page, not the view" '.refs[0].page_id == "01234567-89ab-cdef-0123-456789abcdef"'
expect_exit 0 "a notion.site page" -- "$S/input-refs" "voir https://acme.notion.site/Spec-0123456789abcdef0123456789abcdef."
expect_jq "trailing punctuation dropped" '.refs[0].kind == "notion" and (.refs[0].url | endswith("abcdef"))'
expect_exit 0 "an issue link" -- "$S/input-refs" "fix https://github.com/acme/app/issues/12"
expect_jq "github-issue" '.refs == [{kind: "github-issue", url: "https://github.com/acme/app/issues/12", repo: "acme/app", number: 12}]'
expect_exit 0 "a plain prompt" -- "$S/input-refs" "Add an Export button to the Campaigns page of acme/app"
expect_jq "no source" '.refs == [] and .kinds == []'
expect_exit 0 "another link" -- "$S/input-refs" "like on https://example.com/doc"
expect_jq "kept as url" '.refs == [{kind: "url", url: "https://example.com/doc"}]'
expect_exit 0 "a file name that does not exist" -- "$S/input-refs" "voir docs/nope.md"
expect_jq "no file" '.refs == []'
out="$(printf 'from stdin %s' "$NOTION" | "$S/input-refs")"
expect_jq "the request on stdin" '.kinds == ["notion"]'
expect_exit 0 "two Notion pages" -- "$S/input-refs" "spec https://www.notion.so/acme/B-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, context https://www.notion.so/acme/A-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
expect_jq "refs keep the order of the request (the first one is the spec)" '[.refs[].page_id] == ["bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]'
expect_exit 2 "nothing to read" -- "$S/input-refs" "   "

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
