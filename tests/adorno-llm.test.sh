#!/usr/bin/env bash
# Tests for src/skills/adorno-llm/scripts/llm-run against a fake curl. No network.
# Usage: tests/adorno-llm.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/src/skills/adorno-llm/scripts/llm-run"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/curl"; ln -s "$ROOT/tests/fake-curl" "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH" FAKE_CURL_DIR="$TMP/curl"
unset ADORNO_DRY_RUN OPENROUTER_API_KEY
# the routes a key may go to: those of the registry bin/kit install writes
export HOME="$TMP/home"; mkdir -p "$HOME/.adorno"
cat >"$HOME/.adorno/registry.json" <<'JSON'
{"defaults": {"models": {"routes": {
  "or": {"base_url": "https://openrouter.ai/api/v1", "model": "qwen/qwen3-coder", "api_key_env": "OPENROUTER_API_KEY"},
  "ours": {"base_url": "https://llm.acme.test/v1/", "model": "acme-7b", "api_key_env": "ACME_LLM_KEY"}}}}}
JSON

pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err" </dev/null)"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(cat "$TMP/err")"; fi
}
expect_jq() { if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $out"; fi; }

printf 'Classify this.\n' >"$TMP/prompt.md"; printf 'You are a triager.\n' >"$TMP/role.md"
OR=(--base-url https://openrouter.ai/api/v1 --model qwen/qwen3-coder)

echo "llm-run"
expect_exit 2 "usage" -- "$R" --model x "$TMP/prompt.md"
expect_exit 4 "plain http refused" -- "$R" --base-url http://example.com/v1 --model x "$TMP/prompt.md"
expect_exit 3 "missing key" -- "$R" "${OR[@]}" "$TMP/prompt.md"
ADORNO_DRY_RUN=1 expect_exit 0 "dry run" -- "$R" "${OR[@]}" --system "$TMP/role.md" --max-tokens 500 "$TMP/prompt.md"
expect_jq "dry run: request without key" \
  '.url == "https://openrouter.ai/api/v1/chat/completions" and .request.messages[0].role == "system" and .request.max_tokens == 500 and .key_env == "OPENROUTER_API_KEY"'
OPENROUTER_API_KEY=sk-test expect_exit 0 "call" -- "$R" "${OR[@]}" --system "$TMP/role.md" "$TMP/prompt.md"
expect_jq "answer and usage" '.content == "hello" and .model == "m-x" and .usage.prompt_tokens == 12 and .finish_reason == "stop"'
jq -e '.model == "qwen/qwen3-coder" and .messages[1].content == "Classify this.\n"' "$TMP/curl/request.json" >/dev/null \
  && ok "request body" || ko "request body"
grep -q 'Bearer sk-test' "$TMP/curl/auth" && ok "key sent in a header file, not argv" || ko "key in header"
grep -rq sk-test "$TMP/curl/request.json" && ko "key leaked into body" || ok "key not in the body"
ACME_LLM_KEY=k2 expect_exit 0 "custom key variable" -- "$R" --base-url https://llm.acme.test/v1 --model acme-7b --key-env ACME_LLM_KEY "$TMP/prompt.md"
OPENROUTER_API_KEY=k expect_exit 4 "an undeclared host is refused" -- "$R" --base-url https://evil.example/v1 --model x "$TMP/prompt.md"
ACME_LLM_KEY=k expect_exit 4 "a declared host with another route's key is refused" -- "$R" "${OR[@]}" --key-env ACME_LLM_KEY "$TMP/prompt.md"
GH_TOKEN=x expect_exit 2 "a non-model key variable is refused" -- "$R" "${OR[@]}" --key-env GH_TOKEN "$TMP/prompt.md"
expect_exit 4 "localhost look-alike refused" -- "$R" --base-url http://localhost.attacker.example/v1 --model x "$TMP/prompt.md"
expect_exit 4 "user info refused" -- "$R" --base-url http://127.0.0.1@evil.example/v1 --model x "$TMP/prompt.md"
expect_exit 4 "https with user info refused" -- "$R" --base-url https://user@openrouter.ai/api/v1 --model x "$TMP/prompt.md"
OPENROUTER_API_KEY='a"b' expect_exit 3 "a key with a quote is refused" -- "$R" "${OR[@]}" "$TMP/prompt.md"
expect_exit 0 "local model needs no key" -- "$R" --base-url http://localhost:11434/v1 --model llama3 "$TMP/prompt.md"
OPENROUTER_API_KEY=sk FAKE_CURL_CODE=429 FAKE_CURL_BODY='{"error":{"message":"rate limited"}}' \
  expect_exit 6 "endpoint error" -- "$R" "${OR[@]}" "$TMP/prompt.md"
grep -q "rate limited" "$TMP/err" && ok "error message surfaced" || ko "error message surfaced"
OPENROUTER_API_KEY=sk expect_exit 0 "prompt from stdin" -- sh -c "echo hi | \"$R\" ${OR[*]} -"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
