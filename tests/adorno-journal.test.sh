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
valid() { python3 "$J" validate "$@"; }
# open_run ID SESSION [EXPIRES] — what run-begin writes: the grant, and where the run's journal goes
open_run() {
  jq -n --arg id "$1" --arg s "$2" --argjson exp "${3:-$(( $(date +%s) + 3600 ))}" --arg j "$KH/runs/test-$1" \
    '{id: $id, session: $s, workflow: "workflow:test:run", expires: $exp, journal: $j}' >"$KH/runs/active/$1.json"
}
last() { out="$(tail -n 1 "$KH/runs/test-$1/events.jsonl" 2>/dev/null)"; }
lines() { wc -l <"$KH/runs/test-$1/events.jsonl" 2>/dev/null | tr -d ' '; }

echo "schema"
expect_exit 0 "the fixture journals are valid" -- valid "$FIX"/feature-build-*/events.jsonl "$FIX"/pr-review-*/*.jsonl
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
  python3 "$J" validate --schema "$TMP/schema.json" "$TMP/bad.jsonl"

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
grep -q "is not one of" "$TMP/err" && [ "$(lines 20260101T100000-1-1)" = "$n" ] && ok "said on stderr, nothing written" || ko "unknown type"
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
# a secret across the excerpt's cut (character 500): redacted whole, never cut first then written in part
pad="$(printf 'x%.0s' $(seq 1 486))"
for secret in "$GH" "https://bob:$PW@example.test/x"; do
  text="$pad $secret and the rest"
  python3 "$J" event message "$(jq -n --arg t "$text" '{from: "you", to: "session", kind: "prompt", text: $t}')" --session sess-a
  last 20260101T100000-1-1
  expect_jq "a text whose secret crosses character 500 is cut after redaction (${secret:0:12}…)" \
    '(.excerpt | length) == 501 and (.excerpt | test("ghp_|bob:") | not) and (.excerpt | test(" \\[red|https://\\[red")) and .chars == '"${#text}"' and .hash == "'"$(printf '%s' "$text" | shasum -a 256 | cut -d' ' -f1)"'"'
done
grep -q "ghp_" "$f" && ko "part of a token crossing the cut reached the journal" || ok "no part of a token crossing the cut is written"
grep -q "hunter2" "$f" && ko "a URL password crossing the cut reached the journal" || ok "no URL password crossing the cut is written"
# the shapes Bash commands carry most
cmd='curl -u admin:hunter3pw https://x.test; S=sk_live_0123456789abcdefABCD; G=glpat-0123456789abcdefghijKL; TOKEN="abc defquoted" ./run --token "two wordsquoted"; curl --user=bob:pw4sure x'
python3 "$J" event tool.call "$(jq -n --arg c "$cmd" '{tool: "Bash", input: $c}')" --session sess-a
last 20260101T100000-1-1
for secret in hunter3pw sk_live_0123 glpat-0123 defquoted wordsquoted pw4sure; do
  grep -q -- "$secret" "$f" && ko "leaked: $secret" || ok "never written: $secret"
done
expect_jq "... and the command stays readable" '.input | test("^curl -u \\[redacted:credentials\\] https://x.test; ") and test("TOKEN=\"\\[redacted:secret\\]\" ./run --token \"\\[redacted:secret\\]\"")'
# redaction is linear: a long unbroken token (a base64 blob, a minified line) costs no more than its length
timed() {  # timed SECONDS CMD… — how long CMD took, or "timeout"
  python3 -c 'import subprocess, sys, time
t = time.time()
try:
    subprocess.run(sys.argv[2:], timeout=float(sys.argv[1]), stdout=subprocess.DEVNULL)
except subprocess.TimeoutExpired:
    sys.exit(print("timeout"))
print(f"{time.time() - t:.2f}")' "$@"
}
fast() { case "$1" in timeout) return 1 ;; esac; python3 -c 'import sys; sys.exit(float(sys.argv[1]) >= 1)' "$1"; }
for c in a -; do
  run="$(head -c 51200 /dev/zero | tr '\0' "$c")"
  took="$(timed 5 python3 "$J" event tool.call "$(jq -n --arg c "$run" '{tool: "Bash", input: $c}')" --session sess-a)"
  last 20260101T100000-1-1
  fast "$took" && jq -e '(.input | length) == 2001' >/dev/null <<<"$out" && ok "50 KB of '$c' as an input: ${took}s, cut to its limit" || ko "50 KB of '$c' as an input" "$took"
  took="$(timed 5 python3 "$J" event model.turn "$(jq -n --arg r "$run" '{model: "m", tokens: {in: 0, out: 0, cache_read: 0, cache_write: 0}, reasoning: $r}')" --session sess-a)"
  last 20260101T100000-1-1
  fast "$took" && jq -e '(.reasoning | length) == 51200' >/dev/null <<<"$out" && ok "50 KB of '$c' as reasoning, redacted whole: ${took}s" || ko "50 KB of '$c' as reasoning" "$took"
done
kit_names="$(grep -o 'SECRET_ENV_RE = re.compile(r"[^"]*"' "$ROOT/bin/kit" | sed 's/.*r"//; s/"$//')"
grep -qF "SECRET_NAME = r\"$kit_names\"" "$J" && ok "same secret names as bin/kit (SECRET_ENV_RE)" || ko "secret names differ from bin/kit" "$kit_names"

echo "hooks (Claude Code payloads, shapes read on 2.1.325)"
open_run 20260101T100000-7-7 sess-h
H="$KH/runs/test-20260101T100000-7-7/events.jsonl"
hook() { printf '%s' "$1" | python3 "$J" hook; }   # hook PAYLOAD
hl() { out="$(tail -n 1 "$H" 2>/dev/null)"; }
common='"session_id":"sess-h","transcript_path":"/synthetic/sess-h.jsonl","cwd":"/synthetic"'
hook "{\"hook_event_name\":\"SessionStart\",$common,\"source\":\"startup\"}"; hl
expect_jq "SessionStart" '.type == "session" and .kind == "start" and .source == "startup" and .transcript == "/synthetic/sess-h.jsonl" and .actor == "session"'
hook "{\"hook_event_name\":\"UserPromptSubmit\",$common,\"prompt\":\"Add pagination\",\"permission_mode\":\"default\"}"; hl
expect_jq "UserPromptSubmit: the owner speaks to the session" '.type == "message" and .actor == "you" and .from == "you" and .to == "session" and .kind == "prompt" and .excerpt == "Add pagination"'
n="$(wc -l <"$H")"
hook "{\"hook_event_name\":\"UserPromptSubmit\",$common,\"prompt\":\"<task-notification>agent done</task-notification>\"}"
[ "$(wc -l <"$H")" = "$n" ] && ok "a background-agent notification is not the owner speaking" || ko "task notification recorded as a prompt"
hook "{\"hook_event_name\":\"SubagentStart\",$common,\"agent_id\":\"a1b2\",\"agent_type\":\"adorno-agent-review-code\"}"; hl
expect_jq "SubagentStart: the session spawns an agent" '.type == "agent.spawn" and .actor == "session" and .parent == null and .agent == {"id": "a1b2", "type": "adorno-agent-review-code"} and .tool == "claude"'
hook "{\"hook_event_name\":\"PostToolUse\",$common,\"tool_name\":\"Agent\",\"duration_ms\":4,\"tool_input\":{\"description\":\"review\",\"prompt\":\"Review the diff\",\"subagent_type\":\"adorno-agent-review-code\"},\"tool_response\":{\"isAsync\":true,\"status\":\"async_launched\",\"agentId\":\"a1b2\",\"resolvedModel\":\"claude-opus-5-5\"}}"; hl
expect_jq "the Agent call links the instance to its prompt and its model" \
  '.type == "tool.call" and .tool == "Agent" and .input == "adorno-agent-review-code: review" and .agent.id == "a1b2" and .model == "claude-opus-5-5" and .excerpt == "Review the diff" and .dur == 4'
hook "{\"hook_event_name\":\"PostToolUse\",$common,\"agent_id\":\"a1b2\",\"agent_type\":\"adorno-agent-review-code\",\"tool_name\":\"Bash\",\"duration_ms\":422,\"tool_input\":{\"command\":\"git diff master...HEAD\",\"description\":\"d\"},\"tool_response\":{\"stdout\":\"+ a line\",\"stderr\":\"\",\"interrupted\":false}}"; hl
expect_jq "a tool call inside a subagent belongs to that agent" \
  '.type == "tool.call" and .actor == "agent:a1b2" and .parent == "session" and .tool == "Bash" and .input == "git diff master...HEAD" and .excerpt == "+ a line" and .dur == 422'
hook "{\"hook_event_name\":\"PostToolUse\",$common,\"tool_name\":\"Edit\",\"duration_ms\":20,\"tool_input\":{\"file_path\":\"src/a.ts\",\"old_string\":\"const password = 1\",\"new_string\":\"const x = 2\"},\"tool_response\":{\"filePath\":\"src/a.ts\"}}"; hl
expect_jq "an edit is its path, never the code it carried" '.tool == "Edit" and .input == "src/a.ts" and (has("excerpt") | not)'
grep -q "const x = 2" "$H" && ko "edited code reached the journal" || ok "the edited code is not in the journal"
hook "{\"hook_event_name\":\"PostToolUse\",$common,\"tool_name\":\"mcp__slack__send_message\",\"duration_ms\":300,\"tool_input\":{\"channel_id\":\"C0123ABC\",\"text\":\"Shipping tonight, details below\",\"reply_broadcast\":false,\"limit\":3,\"blocks\":[{\"text\":\"x\"}],\"thread_ts\":\"1712345678.000100\"},\"tool_response\":{\"ok\":true}}"; hl
expect_jq "a tool the journal does not know (MCP): its identifiers, never its content" \
  '.tool == "mcp__slack__send_message" and (.input | fromjson) == {"channel_id": "C0123ABC", "text": "…", "reply_broadcast": false, "limit": 3, "blocks": "…", "thread_ts": "1712345678.000100"}'
grep -q "Shipping tonight" "$H" && ko "an MCP message's text reached the journal" || ok "an MCP message's text is not in the journal"
hook "{\"hook_event_name\":\"PostToolUseFailure\",$common,\"tool_name\":\"Bash\",\"duration_ms\":8000,\"tool_input\":{\"command\":\"npm test\"},\"error\":\"1 failing\",\"is_interrupt\":false}"; hl
expect_jq "a failed tool call" '.type == "tool.call" and .error == true and .excerpt == "1 failing" and .dur == 8000'
hook "{\"hook_event_name\":\"PostToolUse\",$common,\"tool_name\":\"AskUserQuestion\",\"duration_ms\":720000,\"tool_input\":{\"questions\":[{\"question\":\"Validate the plan?\",\"header\":\"Plan\",\"options\":[]}]},\"tool_response\":{\"answers\":{\"Validate the plan?\":\"Yes\"}}}"; hl
expect_jq "a question to the owner is a checkpoint, with its answer and how long it waited" \
  '.type == "checkpoint" and .question == "Validate the plan?" and .answer == "Yes" and .by == "you" and .dur == 720000'
hook "{\"hook_event_name\":\"SubagentStop\",$common,\"agent_id\":\"a1b2\",\"agent_type\":\"adorno-agent-review-code\",\"agent_transcript_path\":\"/synthetic/sess-h/subagents/agent-a1b2.jsonl\",\"last_assistant_message\":\"Review written\"}"; hl
expect_jq "SubagentStop: the agent returns, with where its transcript is" \
  '.type == "agent.return" and .actor == "agent:a1b2" and .agent.id == "a1b2" and .transcript == "/synthetic/sess-h/subagents/agent-a1b2.jsonl" and .excerpt == "Review written"'
hook "{\"hook_event_name\":\"Stop\",$common,\"last_assistant_message\":\"Done.\",\"stop_hook_active\":false}"; hl
expect_jq "Stop: the session answers the owner" '.type == "message" and .from == "session" and .to == "you" and .kind == "reply" and .excerpt == "Done."'
hook "{\"hook_event_name\":\"PostCompact\",$common,\"trigger\":\"auto\"}"; hl
expect_jq "PostCompact" '.type == "session" and .kind == "compact" and .source == "auto"'
hook "{\"hook_event_name\":\"SessionEnd\",$common,\"reason\":\"other\"}"; hl
expect_jq "SessionEnd" '.type == "session" and .kind == "end" and .source == "other"'
n="$(wc -l <"$H")"
hook "{\"hook_event_name\":\"Notification\",$common,\"message\":\"x\"}"; hook 'not json' 2>/dev/null; hook '{}'
[ "$(wc -l <"$H")" = "$n" ] && ok "an event the journal does not map, or a broken payload, writes nothing and fails nothing" || ko "unmapped hook event written"
hook "{\"hook_event_name\":\"Stop\",\"session_id\":\"sess-other\",\"last_assistant_message\":\"x\"}"
[ "$(wc -l <"$H")" = "$n" ] && ok "a session without an open run is not recorded" || ko "foreign session recorded"
expect_exit 0 "every event the hooks wrote is valid" -- valid "$H"
rm -f "$KH/runs/active/20260101T100000-7-7.json"

echo "enrich (synthetic Claude Code transcripts)"
TR="$TMP/claude/projects/x"; mkdir -p "$TR"; cp -R "$FIX/transcripts/." "$TR/"
ER=20260101T100000-8-8; open_run "$ER" sess-e; ED="$KH/runs/test-$ER"
ev() { python3 "$J" event "$@" --run "$ER" --session sess-e; }
ev run.begin '{"t":"2026-01-01T10:00:00.000Z","workflow":"workflow:test:run","mode":"auto","level":"L1","repos":["acme/app"],"dir":"/synthetic"}'
ev message "$(jq -n --arg p "$TR/sess-e.jsonl" '{t: "2026-01-01T10:00:01.000Z", from: "you", to: "session", kind: "prompt", text: "Review the branch", transcript: $p}')" --actor you
ev agent.return "$(jq -n --arg p "$TR/sess-e/subagents/agent-a9.jsonl" '{t: "2026-01-01T10:00:07.500Z", agent: {id: "a9", type: "adorno-agent-review-code"}, text: "Review written", transcript: $p}')" --actor agent:a9
ev message '{"t":"2026-01-01T10:00:12.500Z","from":"session","to":"you","kind":"reply","text":"Done."}'
ev run.end '{"t":"2026-01-01T10:30:00.100Z","workflow":"workflow:test:run","outcome":"ended"}'
rm -f "$KH/runs/active/$ER.json"
expect_exit 0 "enrich a closed run, by its id" -- python3 "$J" enrich "$ER"
expect_jq "says what it read" '.transcripts == 2 and .model_turns == 3 and .messages == 1 and (.file | endswith("/enriched.jsonl"))'
out="$(jq -cs . "$ED/enriched.jsonl")"
expect_jq "one model.turn per response: the blocks of one request are one turn, its usage counted once" \
  '[.[] | select(.type == "model.turn" and .actor == "session")] | length == 2 and .[0].tokens == {"in":100,"out":50,"cache_read":1000,"cache_write":200}
   and .[0].model == "claude-sonnet-5-5" and .[0].stop == "tool_use" and .[0].thinking_tokens == 30 and .[0].thinking_ms == 400'
expect_jq "a turn starts when its request is sent and lasts until its last block" \
  '[.[] | select(.type == "model.turn" and .actor == "session")] | .[0].t == "2026-01-01T10:00:02.000Z" and .[0].dur == 2000 and .[1].t == "2026-01-01T10:00:10.000Z" and .[1].dur == 2000'
expect_jq "a subagent's turns are its own" \
  'any(.[]; .type == "model.turn" and .actor == "agent:a9" and .parent == "session" and .model == "claude-opus-5-5" and .tokens.cache_write == 4000 and .t == "2026-01-01T10:00:05.000Z")'
expect_jq "what happened before the run opened or after it closed is not the run's" \
  'all(.[]; .t >= "2026-01-01T10:00:00.000Z" and .t <= "2026-01-01T10:30:00.000Z") and all(.[]; (.excerpt // "") | test("Before|After") | not)'
expect_jq "a text the model wrote: excerpt, hash, and where the whole is" \
  '[.[] | select(.type == "message")] | length == 1 and .[0].excerpt == "I will delegate the review." and .[0].from == "session" and .[0].to == "you" and .[0].kind == "text"
   and (.[0].ref.file | endswith("/sess-e.jsonl")) and .[0].ref.id == "u-3" and (.[0].hash | length) == 64'
expect_jq "a text the hooks already recorded (the reply, the agent's return) is not written twice" \
  'all(.[]; .excerpt != "Done." and .excerpt != "Review written")'
expect_jq "reasoning is not copied unless the owner asked" 'all(.[]; has("reasoning") | not)'
expect_exit 0 "enriched events are valid" -- valid "$ED/enriched.jsonl"
[ "$(stat -f %Lp "$ED/enriched.jsonl" 2>/dev/null || stat -c %a "$ED/enriched.jsonl")" = 600 ] && ok "readable by its owner only" || ko "enriched.jsonl mode"
before="$(cksum <"$ED/enriched.jsonl")"; n="$(wc -l <"$ED/events.jsonl")"
python3 "$J" enrich "test-$ER" >/dev/null
[ "$(cksum <"$ED/enriched.jsonl")" = "$before" ] && [ "$(wc -l <"$ED/events.jsonl")" = "$n" ] \
  && ok "running it again changes nothing (events.jsonl is never rewritten)" || ko "enrich is not idempotent"
printf '{"journal": {"reasoning": true}}' >"$KH/registry.json"
python3 "$J" enrich "$ER" >/dev/null; out="$(jq -cs . "$ED/enriched.jsonl")"
expect_jq "journal.reasoning: true copies the reasoning the transcript holds (an empty one stays absent)" \
  '[.[] | select(.type == "model.turn")] | (map(select(.actor == "agent:a9"))[0].reasoning == "Compare both branches.") and all(.[] | select(.actor == "session"); has("reasoning") | not)'
rm -f "$KH/registry.json"
rm -f "$TR/sess-e/subagents/agent-a9.jsonl"
expect_exit 0 "a transcript Claude Code pruned: the rest is still read" -- python3 "$J" enrich "$ER"
expect_jq "... and it says which one is missing" '.transcripts == 1 and .model_turns == 2'
grep -q "transcript not found" "$TMP/err" && ok "... on stderr" || ko "missing transcript not reported"
# a token across character 500 in a text block and in a thinking block of the transcripts: redacted, then cut
TS="$TMP/claude/projects/secret"; mkdir -p "$TS/sess-s/subagents"
sed "s|I will delegate the review.|$pad $GH then more|" "$FIX/transcripts/sess-e.jsonl" >"$TS/sess-s.jsonl"
sed "s|Compare both branches.|$pad $GH compared|" "$FIX/transcripts/sess-e/subagents/agent-a9.jsonl" >"$TS/sess-s/subagents/agent-a9.jsonl"
grep -q "$GH" "$TS/sess-s.jsonl" && grep -q "$GH" "$TS/sess-s/subagents/agent-a9.jsonl" && ok "the transcripts hold the token" || ko "transcript copies"
SR=20260101T100000-6-6; open_run "$SR" sess-s; SD="$KH/runs/test-$SR"
sv() { python3 "$J" event "$@" --run "$SR" --session sess-s; }
sv run.begin '{"t":"2026-01-01T10:00:00.000Z","workflow":"workflow:test:run","mode":"auto","level":"L1","repos":["acme/app"],"dir":"/synthetic"}'
sv message "$(jq -n --arg p "$TS/sess-s.jsonl" '{t: "2026-01-01T10:00:01.000Z", from: "you", to: "session", kind: "prompt", text: "Review", transcript: $p}')" --actor you
sv agent.return "$(jq -n --arg p "$TS/sess-s/subagents/agent-a9.jsonl" '{t: "2026-01-01T10:00:07.500Z", agent: {id: "a9"}, text: "Review written", transcript: $p}')" --actor agent:a9
sv run.end '{"t":"2026-01-01T10:30:00.100Z","workflow":"workflow:test:run","outcome":"ended"}'
rm -f "$KH/runs/active/$SR.json"
for reasoning in false true; do
  printf '{"journal": {"reasoning": %s}}' "$reasoning" >"$KH/registry.json"
  expect_exit 0 "enrich, journal.reasoning: $reasoning" -- python3 "$J" enrich "$SR"
  out="$(jq -cs . "$SD/enriched.jsonl")"
  expect_jq "... the text is there, cut after its redaction" \
    'any(.[]; .type == "message" and (.excerpt | startswith("xxx")) and (.excerpt | length) == 501 and (.excerpt | test("ghp_") | not))'
  [ "$reasoning" = false ] || expect_jq "... and the reasoning, redacted" 'any(.[]; .type == "model.turn" and ((.reasoning // "") | test("\\[redacted:github\\] compared")))'
  grep -q "ghp_" "$SD/enriched.jsonl" && ko "... a token crossing the cut reached enriched.jsonl" || ok "... no part of the token in enriched.jsonl"
done
rm -f "$KH/registry.json"
expect_exit 0 "an unknown run fails nothing" -- python3 "$J" enrich 20990101T000000-1-1
grep -q "no journal for run" "$TMP/err" && ok "... and says so" || ko "unknown run not reported"

echo "prune"
old_run="$KH/runs/old-20250101T000000-1-1"; kept_run="$KH/runs/kept-20250101T000000-2-2"; open_old="$KH/runs/test-20260101T000000-9-9"
mkdir -p "$old_run" "$kept_run/reviews" "$open_old"
for d in "$old_run" "$kept_run" "$open_old"; do echo '{}' >"$d/events.jsonl"; touch -t 202501010000 "$d/events.jsonl"; done
echo '{}' >"$kept_run/reviews/code.json"; touch -t 202501010000 "$kept_run/reviews/code.json"
open_run 20260101T000000-9-9 sess-z
expect_exit 0 "prune" -- python3 "$J" prune
[ ! -e "$old_run" ] && ok "an old journal goes, and its emptied folder with it" || ko "old journal kept"
[ ! -e "$kept_run/events.jsonl" ] && [ -f "$kept_run/reviews/code.json" ] && ok "only the journal goes: the run's other files stay" || ko "deliverables removed"
[ -f "$open_old/events.jsonl" ] && ok "the journal of an open run stays, whatever its age" || ko "open run pruned"
[ -f "$f" ] && ok "a recent journal stays" || ko "recent journal pruned"
rm -f "$KH/runs/active/20260101T000000-9-9.json"
# the owner's settings: no age limit to speak of, one megabyte in all
printf '{"journal": {"retention_days": 100000, "max_mb": 1}}' >"$KH/registry.json"
big1="$KH/runs/big-20260101T000000-1-1"; big2="$KH/runs/big-20260201T000000-2-2"; mkdir -p "$big1" "$big2"
head -c 700000 /dev/zero >"$big1/enriched.jsonl"; touch -t 202601010000 "$big1/enriched.jsonl"
head -c 700000 /dev/zero >"$big2/events.jsonl"; touch -t 202602010000 "$big2/events.jsonl"
expect_exit 0 "prune with the owner's settings" -- python3 "$J" prune
[ ! -e "$big1" ] && [ -f "$big2/events.jsonl" ] && ok "over max_mb, the oldest journals go first, until the rest fits" || ko "size cap"
[ ! -e "$open_old/events.jsonl" ] && ok "... an old journal whose run is closed among them" || ko "closed old journal kept over the cap"
[ -f "$f" ] && ok "retention_days is the owner's: a journal within it stays" || ko "journal pruned within retention"
rm -f "$KH/registry.json"

echo "recording never breaks the caller"
chmod 500 "$KH/runs/test-20260101T100000-1-1"; chmod 400 "$f"
expect_exit 0 "a journal that cannot be written" -- python3 "$J" event loop '{"round":1,"cap":2}' --session sess-a
grep -q "not recorded" "$TMP/err" && ok "said on stderr" || ko "silent failure" "$(cat "$TMP/err")"
chmod 700 "$KH/runs/test-20260101T100000-1-1"; chmod 600 "$f"
# a full disk, simulated: no file may grow (the reason is read through a pipe, since no file can take it either)
n="$(wc -l <"$f")"
expect_exit 0 "a disk that takes no more" -- sh -c "ulimit -f 0; python3 '$J' event loop '{\"round\":1,\"cap\":2}' --session sess-a 2>&1 | cat"
case "$out" in *"not recorded"*) ok "said, and the caller goes on" ;; *) ko "a failed write was silent" "$out" ;; esac
[ "$(wc -l <"$f")" = "$n" ] && ok "the journal is left as it was, no half line" || ko "the journal changed on a failed write"
expect_exit 0 "no arguments" -- python3 "$J"
expect_exit 0 "a broken run file is skipped" -- sh -c "printf '{' >'$KH/runs/active/broken.json'; python3 '$J' event loop '{\"round\":1,\"cap\":2}' --session sess-a"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
