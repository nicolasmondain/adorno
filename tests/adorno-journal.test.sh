#!/usr/bin/env bash
# Tests for src/skills/adorno-journal: the event format, the writer and its redaction. No network.
# Usage: tests/adorno-journal.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
J="$ROOT/src/skills/adorno-journal/scripts/journal.py"
SCHEMA="$ROOT/src/skills/adorno-journal/schema.json"
FIX="$ROOT/tests/fixtures/journal"
TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
# a throwaway home: journals live under ~/.adorno/runs only
export HOME="$TMP/home"; KH="$HOME/.adorno"; mkdir -p "$KH/runs/active"
unset CLAUDE_CODE_SESSION_ID

pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err")"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(cat "$TMP/err")"; fi
}
expect_jq() { if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $out"; fi; }
valid() { python3 "$ROOT/tests/jsonschema_subset.py" "$SCHEMA" "$@"; }
# open_run ID SESSION [EXPIRES] — what run-begin writes: the grant, and where the run's journal goes
open_run() {
  jq -n --arg id "$1" --arg s "$2" --argjson exp "${3:-$(( $(date +%s) + 3600 ))}" --arg j "$KH/runs/test-$1" \
    '{id: $id, session: $s, workflow: "workflow:test:run", expires: $exp, journal: $j}' >"$KH/runs/active/$1.json"
}
last() { out="$(tail -n 1 "$KH/runs/test-$1/events.jsonl" 2>/dev/null)"; }
lines() { wc -l <"$KH/runs/test-$1/events.jsonl" 2>/dev/null | tr -d ' '; }

echo "schema"
expect_exit 0 "the fixture journal is valid" -- valid "$FIX"/*/events.jsonl
types="$(jq -r '.properties.type.enum[]' "$SCHEMA" | sort | tr '\n' ' ')"
seen="$(jq -r .type "$FIX"/feature-build-*/events.jsonl | sort -u | tr '\n' ' ')"
[ "$types" = "$seen" ] && ok "the fixture holds every event type" || ko "every type in the fixture" "schema: $types / fixture: $seen"
base='{"v":1,"t":"2026-01-01T10:00:00.000Z","run":"20260101T100000-1-1","session":"s","actor":"session","parent":null'
bad() { printf '%s\n' "$base,$2}" >"$TMP/bad.jsonl"; expect_exit 1 "refused: $1" -- valid "$TMP/bad.jsonl"; }
bad "a type without its required fields" '"type":"guard","decision":"deny"'
bad "an unknown field" '"type":"loop","round":1,"cap":2,"oops":true'
bad "an unknown type" '"type":"nope"'
bad "a value outside its enum" '"type":"guard","decision":"allow","reason":"r","command":"c"'
bad "a wrong value type" '"type":"script.call","script":"x","exit":"0"'
bad "a session kind outside its enum" '"type":"session","kind":"pause"'
printf '%s\n' "${base/session\",\"parent/bot\",\"parent},\"type\":\"loop\",\"round\":1,\"cap\":2}" >"$TMP/bad.jsonl"
expect_exit 1 "refused: an unknown actor" -- valid "$TMP/bad.jsonl"
printf '{"type": "object", "maxProperties": 3}' >"$TMP/schema.json"
expect_exit 2 "a schema keyword the checker does not implement is an error, not a pass" -- \
  python3 "$ROOT/tests/jsonschema_subset.py" "$TMP/schema.json" "$TMP/bad.jsonl"

echo "writer"
expect_exit 0 "no run open: nothing happens" -- python3 "$J" event loop '{"round":1,"cap":2}' --session sess-a
[ -z "$(find "$KH/runs" -name events.jsonl)" ] && ok "no journal without a run" || ko "no journal without a run"
open_run 20260101T100000-1-1 sess-a
open_run 20260101T100000-2-2 sess-b
open_run 20260101T100000-3-3 sess-a 1
expect_exit 0 "an event of the session" -- python3 "$J" event loop '{"round":1,"cap":2,"reason":"1 major"}' --session sess-a
last 20260101T100000-1-1
expect_jq "common fields filled, own fields kept" \
  '.v == 1 and .run == "20260101T100000-1-1" and .session == "sess-a" and .actor == "session" and .parent == null
   and .type == "loop" and .round == 1 and .cap == 2 and (.t | test("^20.*Z$"))'
[ ! -e "$KH/runs/test-20260101T100000-2-2" ] && ok "another session's run is not written" || ko "other session"
[ ! -e "$KH/runs/test-20260101T100000-3-3" ] && ok "an expired run is not written" || ko "expired run"
expect_exit 0 "the session comes from CLAUDE_CODE_SESSION_ID" -- \
  env CLAUDE_CODE_SESSION_ID=sess-b python3 "$J" event github '{"action":"push","target":"acme/app"}'
last 20260101T100000-2-2; expect_jq "written to that session's run" '.type == "github" and .session == "sess-b"'
expect_exit 0 "--run names one run, whatever the session" -- \
  python3 "$J" event run.end '{"workflow":"workflow:test:run","outcome":"ended"}' --run 20260101T100000-2-2 --session sess-b
last 20260101T100000-2-2; expect_jq "run.end" '.type == "run.end"'
[ "$(lines 20260101T100000-1-1)" = 1 ] && ok "and only that run" || ko "only that run" "$(lines 20260101T100000-1-1) lines"
expect_exit 0 "an agent's event" -- python3 "$J" event tool.call '{"tool":"Read","input":"a.ts"}' --session sess-a --actor agent:a1
last 20260101T100000-1-1; expect_jq "an agent's parent is the session" '.actor == "agent:a1" and .parent == "session"'
long="$(printf 'x%.0s' $(seq 1 600))"
expect_exit 0 "a text field" -- python3 "$J" event message "$(jq -n --arg t "$long" '{from: "you", to: "session", kind: "prompt", text: $t}')" --session sess-a
last 20260101T100000-1-1
expect_jq "text becomes excerpt + hash + chars" \
  '(has("text") | not) and (.excerpt | length) == 501 and .chars == 600 and (.hash | test("^[0-9a-f]{64}$"))'
expect_exit 0 "stdin input" -- sh -c "printf '%s' '{\"round\":2,\"cap\":2}' | python3 '$J' event loop --session sess-a"
last 20260101T100000-1-1; expect_jq "read from stdin" '.round == 2'
n="$(lines 20260101T100000-1-1)"
expect_exit 0 "an unknown type is refused, the caller goes on" -- python3 "$J" event nope '{}' --session sess-a
grep -q "unknown event type" "$TMP/err" && [ "$(lines 20260101T100000-1-1)" = "$n" ] && ok "said on stderr, nothing written" || ko "unknown type"
expect_exit 0 "invalid JSON is refused, the caller goes on" -- python3 "$J" event loop '{not json' --session sess-a
[ "$(lines 20260101T100000-1-1)" = "$n" ] && ok "nothing written" || ko "invalid JSON written"
expect_exit 0 "every line written is valid" -- valid "$KH"/runs/test-*/events.jsonl
[ "$(stat -f %Lp "$KH/runs/test-20260101T100000-1-1/events.jsonl" 2>/dev/null || stat -c %a "$KH/runs/test-20260101T100000-1-1/events.jsonl")" = 600 ] \
  && ok "a journal is readable by its owner only" || ko "journal mode 600"
for i in 1 2 3 4 5 6 7 8; do python3 "$J" event loop "{\"round\":$i,\"cap\":8}" --session sess-b & done; wait
[ "$(jq -s '[.[] | select(.type == "loop")] | length' "$KH/runs/test-20260101T100000-2-2/events.jsonl")" = 8 ] \
  && ok "parallel writers each get their line" || ko "parallel writers"

echo "a journal never leaves ~/.adorno/runs"
jq --arg j "$TMP/repo/.agent-run/x" '.journal = $j' "$KH/runs/active/20260101T100000-2-2.json" >"$TMP/a.json" && mv "$TMP/a.json" "$KH/runs/active/20260101T100000-2-2.json"
expect_exit 0 "a journal folder elsewhere is refused" -- python3 "$J" event loop '{"round":1,"cap":2}' --session sess-b
[ ! -e "$TMP/repo" ] && grep -q "not a run folder" "$TMP/err" && ok "nothing written outside" || ko "written outside"
jq --arg j "$KH/runs/active" '.journal = $j' "$KH/runs/active/20260101T100000-2-2.json" >"$TMP/a.json" && mv "$TMP/a.json" "$KH/runs/active/20260101T100000-2-2.json"
expect_exit 0 "the grants folder is refused" -- python3 "$J" event loop '{"round":1,"cap":2}' --session sess-b
[ ! -e "$KH/runs/active/events.jsonl" ] && ok "nothing written next to the grants" || ko "written in active/"

echo "redaction"
GH="ghp_0123456789abcdefghijABCDEFGHIJ012345"; SK="sk-ant-0123456789abcdefghij"; PW="hunter2-s3cret"
JWT="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N"
cmd="curl -H 'Authorization: Basic dXNlcjpodW50ZXIy' -H \"X-Api-Key: $SK\" https://bob:$PW@example.test/x?token=$GH && \
export DB_PASSWORD=$PW; mysql --password $PW; echo $JWT; echo AKIAABCDEFGHIJKLMNOP xoxb-1234567890-abcdefghij"
python3 "$J" event tool.call "$(jq -n --arg c "$cmd" --arg p "$PW" --arg k "$SK" \
  '{tool: "Bash", input: $c, text: ("Bearer abcdefgh12345678 then " + $c)}')" --session sess-a
python3 "$J" event script.call "$(jq -n --arg p "$PW" --arg g "$GH" \
  '{script: "x", exit: 0, args: ["--token", $g, "--password=" + $p, "-----BEGIN RSA PRIVATE KEY-----\nMIIEow\n-----END RSA PRIVATE KEY-----"]}')" --session sess-a
f="$KH/runs/test-20260101T100000-1-1/events.jsonl"
for secret in "$GH" "$SK" "$PW" "$JWT" dXNlcjpodW50ZXIy abcdefgh12345678 AKIAABCDEFGHIJKLMNOP xoxb-1234567890 MIIEow; do
  grep -q -- "$secret" "$f" && ko "leaked: $secret" || ok "never written: $secret"
done
last 20260101T100000-1-1
expect_jq "what was removed is named" '.args == ["--token", "[redacted:secret]", "--password=[redacted:secret]", "[redacted:private-key]"]'
out="$(tail -n 2 "$f" | head -n 1)"
expect_jq "the rest of the command stays readable" '(.input | test("^curl -H .Authorization: \\[redacted:authorization\\]")) and (.input | test("example.test/x"))'
python3 "$J" event model.turn '{"model":"m","tokens":{"in":1,"out":2,"cache_read":3,"cache_write":4},"thinking_tokens":5}' --session sess-a
last 20260101T100000-1-1; expect_jq "counts are not secrets" '.tokens == {"in":1,"out":2,"cache_read":3,"cache_write":4} and .thinking_tokens == 5'
python3 "$J" event model.turn "$(jq -n --arg r "$(printf 'y%.0s' $(seq 1 3000)) $GH" \
  '{model: "m", tokens: {in: 0, out: 0, cache_read: 0, cache_write: 0}, reasoning: $r, stop: $r}')" --session sess-a
last 20260101T100000-1-1
expect_jq "reasoning is kept whole and redacted, other strings are cut" \
  '(.reasoning | length) > 3000 and (.reasoning | test("ghp_") | not) and (.stop | length) == 2001'
expect_exit 0 "redacted lines are valid" -- valid "$f"
kit_names="$(grep -o 'SECRET_ENV_RE = re.compile(r"[^"]*"' "$ROOT/bin/kit" | sed 's/.*r"//; s/"$//')"
grep -qF "SECRET_NAME = r\"$kit_names\"" "$J" && ok "same secret names as bin/kit (SECRET_ENV_RE)" || ko "secret names differ from bin/kit" "$kit_names"

echo "recording never breaks the caller"
chmod 500 "$KH/runs/test-20260101T100000-1-1"; chmod 400 "$f"
expect_exit 0 "a journal that cannot be written" -- python3 "$J" event loop '{"round":1,"cap":2}' --session sess-a
grep -q "not recorded" "$TMP/err" && ok "said on stderr" || ko "silent failure" "$(cat "$TMP/err")"
chmod 700 "$KH/runs/test-20260101T100000-1-1"; chmod 600 "$f"
expect_exit 0 "no arguments" -- python3 "$J"
expect_exit 0 "a broken run file is skipped" -- sh -c "printf '{' >'$KH/runs/active/broken.json'; python3 '$J' event loop '{\"round\":1,\"cap\":2}' --session sess-a"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
