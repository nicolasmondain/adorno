#!/usr/bin/env bash
# Tests for `bin/kit serve` (bin/kit_serve.py): the read-only server of the run journals, against synthetic journals
# copied into a throwaway folder. Needs curl. Usage: tests/kit-serve.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; SERVERS=""
stop_servers() { local p; for p in $SERVERS; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; }
trap 'stop_servers; rm -rf "$TMP"' EXIT
# python3 with PyYAML runs bin/kit directly; else uv, keeping its real cache (as tests/kit.test.sh)
if python3 -c 'import yaml' 2>/dev/null; then KIT=(python3 "$ROOT/bin/kit")
elif command -v uv >/dev/null 2>&1; then KIT=("$ROOT/bin/kit")
else echo "needs python3 with PyYAML, or uv" >&2; exit 1; fi
command -v curl >/dev/null 2>&1 || { echo "needs curl" >&2; exit 1; }

pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err" </dev/null)"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(tail -c 300 "$TMP/err")"; fi
}
expect_jq() { if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $(head -c 400 <<<"$out")"; fi; }
# get PATH [curl options…] — the request as written (no path clean-up); status in $code, body in $out, headers in $TMP/head
get() {
  local path="$1"; shift
  code="$(curl -s --path-as-is -o "$TMP/body" -D "$TMP/head" -w '%{http_code}' "$@" "$URL$path")"
  out="$(cat "$TMP/body")"
}
status() { get "$2" "${@:3}"; if [ "$code" = "$1" ]; then ok "$1 · $2"; else ko "$1 · $2" "got $code: $(head -c 200 <<<"$out")"; fi; }
header() { grep -i "^$1:" "$TMP/head" | tr -d '\r' | sed 's/^[^:]*: *//'; }
# wait_url FILE — the URL a server printed when it started listening
wait_url() {
  local tries=0
  until [ -s "$1" ] || [ "$tries" -ge 300 ]; do tries=$((tries + 1)); sleep 0.1; done
  head -n 1 "$1" | sed 's|/$||'
}

# the synthetic journals, as ~/.adorno/runs would hold them: next to the grants, a run without journal and a link
RUNS="$TMP/runs"; FIX="$ROOT/tests/fixtures/journal"
mkdir -p "$RUNS/active" "$RUNS/no-journal-20260101T090000-1-1" "$TMP/elsewhere"
for d in feature-build-20260101T100000-1000-1 pr-review-20260101T120000-1001-2 broken-20260101T130000-1002-3; do
  cp -R "$FIX/$d" "$RUNS/$d"
  for f in "$RUNS/$d"/*.jsonl; do sed -e "s|__RUNS__|$RUNS|g" -e "s|__ROOT__|$TMP|g" "$f" >"$f.tmp" && mv "$f.tmp" "$f"; done
done
echo '{"id": "x"}' >"$RUNS/active/x.json"; echo '{}' >"$RUNS/active/events.jsonl"
echo 'not a journal' >"$RUNS/no-journal-20260101T090000-1-1/notes.md"
cp -R "$RUNS/broken-20260101T130000-1002-3" "$TMP/elsewhere/linked"; ln -s "$TMP/elsewhere/linked" "$RUNS/linked-20260101T140000-1-1"
WS="$TMP/workspaces/acme__app/pr-7/.agent-run/review-1"; mkdir -p "$WS/reviews"
echo '{"verdict": "fix"}' >"$WS/reviews/merged.json"; echo '{"verdict": "pass"}' >"$WS/reviews/code.json"
F1=feature-build-20260101T100000-1000-1; F2=pr-review-20260101T120000-1001-2; F3=broken-20260101T130000-1002-3
echo 'top secret' >"$TMP/elsewhere/secret.md"; ln -s "$TMP/elsewhere/secret.md" "$RUNS/$F1/leak.md"
echo '<script>1</script>' >"$RUNS/$F1/page.html"; mkdir "$RUNS/$F1/folder.md"
head -c 2200000 /dev/zero >"$RUNS/$F1/huge.log"
touch "$TMP/stamp"; sleep 1

echo "start"
expect_exit 2 "port 8000 is refused" -- "${KIT[@]}" serve --port 8000 --runs "$RUNS"
expect_exit 2 "there is no --host: the server listens on this machine only" -- "${KIT[@]}" serve --host 0.0.0.0 --runs "$RUNS"
"${KIT[@]}" serve --port 0 --runs "$RUNS" >"$TMP/url" 2>"$TMP/serve.err" & SERVERS="$SERVERS $!"
URL="$(wait_url "$TMP/url")"; PORT="${URL##*:}"
case "$URL" in http://127.0.0.1:[0-9]*) ok "prints the address it listens on" ;; *) ko "no address printed" "$(cat "$TMP/serve.err")" ;; esac
expect_exit 1 "a port already taken is said, not worked around" -- "${KIT[@]}" serve --port "$PORT" --runs "$RUNS"
bound="$(python3 - "$PORT" <<'EOF'
import socket, sys
port = int(sys.argv[1])
probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    probe.connect(("192.0.2.1", 9))   # no packet is sent: only asks which address would be used
    address = probe.getsockname()[0]
except OSError:
    address = "127.0.0.1"
if address.startswith("127."):
    print("skip"); sys.exit()
try:
    socket.create_connection((address, port), timeout=3).close()
    print("reachable on " + address)
except OSError:
    print("refused")
EOF
)"
case "$bound" in
  refused) ok "not reachable through the machine's network address" ;;
  skip) printf '  SKIP not reachable through the network address (this machine has none)\n' ;;
  *) ko "listens beyond 127.0.0.1" "$bound" ;;
esac

echo "list"
status 200 /api/runs
expect_jq "the runs that have a journal, newest first; not the grants, a run without journal, a linked folder" \
  '[.runs[].id] == ["'"$F3"'", "'"$F2"'", "'"$F1"'"]'
expect_jq "a run: what it was, how long, what it cost" \
  '.runs[2] | .run == "20260101T100000-1000-1" and .workflow == "workflow:feature:build" and .mode == "draft" and .level == "L2" and .repos == ["acme/app"]
   and .start == "2026-01-01T10:00:00.000Z" and .end == "2026-01-01T10:17:10.100Z" and .duration_ms == 1030100 and .outcome == "ended"
   and .agents == 9 and .events == 85 and .bad_lines == 0 and .tokens == {"in": 32900, "out": 5930, "cache_read": 39300, "cache_write": 51800} and .size > 0'
expect_jq "a run still open, its transcripts' turns counted with the rest" \
  '.runs[1] | .outcome == "open" and .end == null and .agents == 3 and .events == 13 and .tokens.in == 2500'
expect_jq "a damaged journal is listed, its unreadable lines counted" '.runs[0] | .bad_lines == 1 and .events == 2 and .workflow == null and .outcome == "open"'
printf '%s\n' '{"v":1,"t":"2026-01-01T13:00:09.000Z","run":"20260101T130000-1002-3","session":"sess-f3","actor":"session","parent":null,"type":"tool.call","tool":"Read","input":"a"}' >>"$RUNS/$F3/events.jsonl"
get /api/runs; expect_jq "a journal that grew is read again" '.runs[0].events == 3'

echo "read"
status 200 "/api/runs/$F1"
expect_jq "events in order, numbered, in milliseconds from the start" \
  '.t0 == "2026-01-01T10:00:00.000Z" and .duration_ms == 1030100 and (.events | length) == 78 and ([.events[].i] == [range(0; 78)])
   and ([.events[].t] | . == sort) and ([.events[].u] | . == sort) and .open == false and .outcome == "ended"'
expect_jq "lanes: you, the session, each agent in spawn order, scripts, the guard, GitHub" \
  '[.lanes[].id] == ["you", "session", "agent:a-plan", "agent:a-build", "agent:a-rev-code", "agent:a-rev-sec", "agent:a-rev-pony",
                     "agent:a-fix-1", "agent:a-rerev-1", "agent:a-fix-2", "agent:a-rerev-2", "scripts", "guard", "github"]'
expect_jq "an agent's lane: what it is, its model (from its Agent call), when it lived" \
  '.lanes[2] | .label == "core-planner" and .agent == "adorno-agent-core-planner" and .instance == "a-plan" and .parent == "session"
   and .model == "claude-fable-5-1" and (has("tier") | not) and .start == 9000 and .end == 60000 and .orphan == false'
expect_jq "what each agent wrote, from its own Write and Edit calls: once each, in order, openable when the run's folders hold it" \
  '(.lanes | map(select(.kind == "agent") | {key: .instance, value: .wrote}) | from_entries) as $w
   | $w["a-plan"] == [{"path": "'"$RUNS/$F1"'/plan.md", "file": "plan.md"}]
   and $w["a-rev-sec"] == [{"path": "'"$RUNS/$F1"'/reviews/security.json", "file": "reviews/security.json"}]
   and $w["a-rev-code"] == [{"path": "'"$RUNS/$F1"'/reviews/code.json", "file": null}]
   and $w["a-build"] == [{"path": "/synthetic/app/src/teams/list.ts", "file": null}]
   and ([.lanes[] | select(.kind != "agent") | has("wrote")] | any | not)'
expect_jq "an agent's return no longer carries a file" 'all(.events[] | select(.type == "agent.return"); (.d | has("file") | not) and (.label | endswith(" returns")))'
expect_jq "the session's model is the one of its turns" '.lanes[1].model == "claude-sonnet-5-5"'
expect_jq "every arrow goes from a lane to a lane" \
  '([.lanes[].id]) as $l | all(.events[]; (.from | IN($l[])) and (.to == null or (.to | IN($l[]))))'
expect_jq "who talks to whom: a spawn, a return, a script, a refusal, a write, a question and its answer" \
  'any(.events[]; .type == "agent.spawn" and .from == "session" and .to == "agent:a-plan")
   and any(.events[]; .type == "agent.return" and .from == "agent:a-plan" and .to == "session")
   and any(.events[]; .type == "script.call" and .from == "session" and .to == "scripts" and .d.script == "pr-open" and .d.exit == 5)
   and any(.events[]; .type == "guard" and .from == "agent:a-rev-sec" and .to == "guard" and .d.decision == "deny")
   and any(.events[]; .type == "github" and .to == "github")
   and any(.events[]; .type == "checkpoint" and .from == "session" and .to == "you" and .t == 61000)
   and any(.events[]; .type == "answer" and .from == "you" and .to == "session" and .t == 781000 and .d.answer == "Yes")'
expect_jq "each event has a sentence to read" 'all(.events[]; (.label | type) == "string" and (.label | length) > 3)
   and any(.events[]; .label == "main session starts core-planner") and any(.events[]; .label == "guard deny: gh pr comment 7 --body looks-fine")'
expect_jq "the plan's steps, as the session marked them" \
  '[.steps[] | [.index, .name, .source]] == [[1, "plan", "journal"], [2, "build", "journal"], [3, "review", "journal"]] and .steps[0].start == 8000 and .steps[0].end == 60500'
expect_jq "the fix rounds, with their cap and the agents started inside" \
  '[.rounds[] | [.round, .cap, .lanes]] == [[1, 2, ["agent:a-fix-1", "agent:a-rerev-1"]], [2, 2, ["agent:a-fix-2", "agent:a-rerev-2"]]]
   and .rounds[0].start == 879000 and .rounds[0].end == 949000 and .rounds[1].end == 1019000 and .rounds[0].reason == "1 major"'
expect_jq "steps and rounds are not marks of their own" 'all(.events[]; .type != "loop" and (.type | startswith("step.") | not)) and .totals.counts.loop == 2'
expect_jq "tokens: per lane and per model, adding up to the total" \
  '.totals.tokens == {"in": 32900, "out": 5930, "cache_read": 39300, "cache_write": 51800}
   and ([.totals.by_lane[].in] | add) == 32900 and ([.totals.by_model[].out] | add) == 5930 and (.totals.by_model | keys | length) == 3
   and .totals.by_lane.session.in == 2800 and .totals.by_lane["agent:a-plan"].cache_read == 9200'
expect_jq "waiting for the owner is idle time: 12 minutes drawn as 5 seconds, marked as a gap" \
  '.time.gap_ms == 5000 and any(.time.segments[]; .gap and .t0 == 61000 and .t1 == 782000 and (.u1 - .u0) == 5000)'
expect_jq "the time map is continuous and increasing, activity keeps its length" \
  '.time.segments as $s | all(range(1; $s | length); $s[.].t0 == $s[. - 1].t1 and $s[.].u0 == $s[. - 1].u1)
   and all($s[]; .gap or (.u1 - .u0) == (.t1 - .t0) or (.t1 - .t0) <= 5000) and $s[-1].t1 == 1030100 and .time.width == $s[-1].u1 and .time.width < 1030100'
expect_jq "the files of the run that can be opened" '[.files[].path] | sort == ["plan.md", "reviews/security.json", "status.md"]'
status 200 "/api/runs/$F2"
expect_jq "an open run: both files read together, an agent without spawn kept apart, one still running" \
  '.open and (.events | length) == 13 and ([.lanes[] | select(.kind == "agent") | [.id, .orphan]] == [["agent:r1", false], ["agent:r2", false], ["agent:zz", true]])
   and (.lanes[] | select(.id == "agent:r1") | .model == "claude-opus-5-5" and .end == 40000) and (.lanes[] | select(.id == "agent:r2") | .end == .start + 34000)'
expect_jq "without marked steps, phases are derived from the delegations and say so" '(.steps | length) == 1 and .steps[0].source == "derived" and .rounds == []'
expect_jq "the files of its .agent-run folder" '[.files[].path] == ["reviews/code.json", "reviews/merged.json"]'
expect_jq "a file an agent wrote in the run's .agent-run folder can be opened" \
  '(.lanes[] | select(.id == "agent:r1") | .wrote) == [{"path": "'"$TMP"'/workspaces/acme__app/pr-7/.agent-run/review-1/reviews/code.json", "file": "reviews/code.json"}]
   and all(.lanes[] | select(.id == "agent:r2" or .id == "agent:zz"); .wrote == [])'
printf '%s\n' '{"v":1,"t":"2026-01-01T12:00:39.500Z","run":"20260101T120000-1001-2","session":"sess-f2","actor":"agent:r1","parent":"session","type":"tool.call","tool":"Edit","input":"'"$TMP"'/workspaces/acme__app/pr-7/src/failed.ts","dur":3,"error":true,"excerpt":"old_string not found","hash":"0000000000000000000000000000000000000000000000000000000000000000","chars":20}' >>"$RUNS/$F2/events.jsonl"
get "/api/runs/$F2"
expect_jq "a failed Edit is not a file the agent wrote" \
  '(.events | length) == 14 and ([.lanes[] | select(.id == "agent:r1") | .wrote[].path] == ["'"$TMP"'/workspaces/acme__app/pr-7/.agent-run/review-1/reviews/code.json"])'
status 200 "/api/runs/$F3"
expect_jq "a damaged journal still reads: what is unknown is kept as a mark" \
  '.bad_lines == 1 and .workflow == null and any(.events[]; .type == "future.thing" and .from == "session" and .to == null)'
for bad in nope active .. %2e%2e "$F1/../$F2" linked-20260101T140000-1-1 no-journal-20260101T090000-1-1; do status 404 "/api/runs/$bad"; done

echo "file"
status 200 "/api/runs/$F1/file?path=plan.md"
[ "$(header content-type)" = "text/plain; charset=utf-8" ] && [ "$(header x-content-type-options)" = "nosniff" ] && grep -q "paginate the teams list" "$TMP/body" \
  && ok "a file of the run, as plain text" || ko "plan.md" "$(header content-type)"
status 200 "/api/runs/$F1/file?path=reviews/security.json"
[ "$(header content-type)" = "application/json; charset=utf-8" ] && ok "json as json" || ko "json content type"
status 200 "/api/runs/$F2/file?path=reviews/merged.json"
for bad in "path=../$F2/events.jsonl" "path=..%2f$F2%2fevents.jsonl" "path=reviews/../../$F2/events.jsonl" "path=$RUNS/$F1/plan.md" "path=" "path=plan.md%00.md" \
           "path=leak.md" "path=page.html" "path=folder.md" "path=missing.md" "x=1"; do
  status 404 "/api/runs/$F1/file?$bad"
done
get "/api/runs/$F1/file?path=leak.md"
grep -q "top secret" "$TMP/body" && ko "a link leaving the run folder was followed" || ok "a link leaving the run folder is not followed"
status 413 "/api/runs/$F1/file?path=huge.log"
sed "s|/.agent-run/review-1|/review-1|" "$RUNS/$F2/events.jsonl" >"$RUNS/$F2/events.tmp" && mv "$RUNS/$F2/events.tmp" "$RUNS/$F2/events.jsonl"
mkdir -p "$TMP/workspaces/acme__app/pr-7/review-1/reviews"; echo '{}' >"$TMP/workspaces/acme__app/pr-7/review-1/reviews/merged.json"
status 404 "/api/runs/$F2/file?path=reviews/merged.json"
get "/api/runs/$F2"; expect_jq "a run folder that is not an .agent-run folder is never read" '.files == [] and (.lanes[] | select(.id == "agent:r1") | .wrote[0].file) == null'

echo "requests"
status 403 /api/runs -H "Host: evil.test"
status 403 /api/runs -H "Host: 127.0.0.1:1"
status 200 /api/runs -H "Host: localhost:$PORT"
status 405 /api/runs -X POST
status 405 "/api/runs/$F1" -X DELETE
get /api/runs -H "Origin: http://evil.test"
[ -z "$(header access-control-allow-origin)" ] && ok "no CORS header, whoever asks" || ko "CORS header sent"
[ "$(header cache-control)" = "no-store" ] && [ "$(header referrer-policy)" = "no-referrer" ] && header content-security-policy | grep -q "default-src 'self'" \
  && ok "nothing is cached, nothing leaks through a referrer, nothing loads from elsewhere" || ko "response headers"
got="$(curl -s --head -o /dev/null -w '%{http_code} %{size_download}' "$URL/api/runs")"
[ "$got" = "200 0" ] && ok "HEAD answers without a body" || ko "HEAD" "$got"
status 404 "/api/runs/$F1/nope"
status 404 /../bin/kit
status 404 /api
get "/api/runs/$F1/file?path=../x.md"; grep -q "x.md" "$TMP/body" && ko "an error echoes what was asked" || ok "an error never echoes what was asked"

echo "the viewer's files"
mkdir -p "$TMP/viewer/fonts"; echo '<!doctype html><title>t</title>' >"$TMP/viewer/index.html"; echo 'body{}' >"$TMP/viewer/a.css"
echo 'export {}' >"$TMP/viewer/app.js"; echo 'x' >"$TMP/viewer/fonts/f.woff2"; echo 'hidden' >"$TMP/viewer/.env"
ln -s "$TMP/elsewhere/secret.md" "$TMP/viewer/linked.txt"
python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import kit_serve; sys.exit(kit_serve.serve(0, sys.argv[2], sys.argv[3]))' \
  "$ROOT/bin" "$RUNS" "$TMP/viewer" >"$TMP/url2" 2>"$TMP/serve2.err" & SERVERS="$SERVERS $!"
URL="$(wait_url "$TMP/url2")"
status 200 /; [ "$(header content-type)" = "text/html; charset=utf-8" ] && header content-security-policy | grep -q "default-src 'self'" \
  && ok "the page, with a policy that loads nothing from elsewhere" || ko "index headers"
status 200 /index.html
status 200 /a.css; [ "$(header content-type)" = "text/css; charset=utf-8" ] && ok "css" || ko "css type"
status 200 /app.js; [ "$(header content-type)" = "text/javascript; charset=utf-8" ] && ok "javascript" || ko "js type"
status 200 /fonts/f.woff2; [ "$(header content-type)" = "font/woff2" ] && ok "fonts" || ko "font type"
for bad in /.env /linked.txt /fonts /fonts/ /../runs/$F1/plan.md /%2e%2e/bin/kit /index.html/ /nope.js; do status 404 "$bad"; done

echo "a run with many idle gaps"
# thousands of the session's tool calls, a silence above GAP_MS every other one: as many segments in the time map
GAPS="$TMP/runs-gaps"; G=gaps-20260103T000000-3000-1; mkdir -p "$GAPS/$G"
python3 - "$GAPS/$G/events.jsonl" <<'EOF'
import json, sys
from datetime import datetime, timedelta, timezone
t0, run = datetime(2026, 1, 3, tzinfo=timezone.utc), "20260103T000000-3000-1"
def event(ms, kind, **fields):
    t = (t0 + timedelta(milliseconds=ms)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    return {"v": 1, "t": t, "run": run, "session": "sess-g", "actor": "session", "parent": None, "type": kind, **fields}
out, ms = [event(0, "run.begin", workflow="workflow:test:gaps", mode="auto", level="L1", repos=["acme/app"], dir="/synthetic")], 0
for i in range(10000):
    ms += 6000 if i % 2 == 0 else 50
    out.append(event(ms, "tool.call", tool="Read", input=f"src/f{i % 40}.ts", dur=20))
out.append(event(ms + 100, "run.end", workflow="workflow:test:gaps", outcome="done"))
with open(sys.argv[1], "w") as f:
    f.writelines(json.dumps(e, separators=(",", ":")) + "\n" for e in out)
EOF
"${KIT[@]}" serve --port 0 --runs "$GAPS" >"$TMP/url3" 2>"$TMP/serve3.err" & SERVERS="$SERVERS $!"
URL="$(wait_url "$TMP/url3")"
took="$(curl -s -o "$TMP/body" -w '%{time_total}' "$URL/api/runs/$G")"; out="$(cat "$TMP/body")"
expect_jq "10 002 events, 10 000 segments or more" '(.events | length) == 10002 and (.time.segments | length) >= 10000 and ([.events[].u] | . == sort)'
python3 -c 'import sys; sys.exit(float(sys.argv[1]) >= 1.5)' "$took" && ok "... read in ${took}s (the walk over the segments is linear)" || ko "a run with many gaps is slow to read" "${took}s"

echo "read-only"
[ -z "$(find "$RUNS" -newer "$TMP/stamp" ! -path "$RUNS/$F3/events.jsonl" ! -path "$RUNS/$F2/events.jsonl" ! -path "$RUNS/$F2" ! -path "$RUNS/$F3")" ] \
  && ok "the server wrote nothing in the runs folder" || ko "the server wrote in the runs folder" "$(find "$RUNS" -newer "$TMP/stamp" | head -5)"
grep -q 'ThreadingHTTPServer(("127.0.0.1", port)' "$ROOT/bin/kit_serve.py" && ! grep -q '0\.0\.0\.0' "$ROOT/bin/kit_serve.py" \
  && ok "the address it binds is written once, and it is 127.0.0.1" || ko "bind address"
[ -z "$(find "$ROOT/bin" -name __pycache__)" ] && ok "no bytecode cache left in bin/" || ko "bin/__pycache__ left behind"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
