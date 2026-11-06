#!/usr/bin/env bash
# Tests for src/skills/adorno-watch/scripts. No network, no connector: messages are fixtures.
# Usage: tests/adorno-watch.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/src/skills/adorno-watch/scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# a throwaway home: the scripts read your settings from ~/.adorno/registry.json only
export HOME="$TMP/home"; mkdir -p "$HOME/.adorno"
FIX="$ROOT/tests/fixtures/watch/adorno.json"
conf() { rm -f "$HOME/.adorno/registry.json"; [ -z "${1:-}" ] || cp "$1" "$HOME/.adorno/registry.json"; }  # conf [FILE]
conf "$FIX"

pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err")"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(cat "$TMP/err")"; fi
}
expect_jq() { if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $out"; fi; }

now="$(date +%s)"
msg() { jq -n --arg id "$1" --argjson ts "$2" --arg t "$3" '{id: $id, channel: "#app-errors", ts: ($ts|tostring), user: "U1", text: $t}'; }
{
  msg C1:1 $((now - 60))      "Request Timeout on /api/teams"
  msg C1:2 $((now - 120))     "deploy ok"
  msg C1:3 $((now - 180))     "slow: took 12034ms"
  msg C1:4 $((now - 240))     "timeout again (lowercase)"
  msg C1:5 $((now - 400000))  "Timeout but too old"
} | jq -s . >"$TMP/msgs.json"

echo "watch-conf"
expect_exit 0 "list" -- "$S/watch-conf" list
expect_jq "lists watches and sections" '.slack_watches == ["exact", "timeouts"] and .slack_mentions and .notion_assigned'
expect_exit 0 "slack watch with defaults" -- "$S/watch-conf" slack-watch timeouts
expect_jq "defaults filled, watch values kept" '.max_messages == 3 and .notify == "draft" and .action.level == "L0" and .case_sensitive == false and .user_id == "U0SELF"'
expect_exit 3 "unknown watch" -- "$S/watch-conf" slack-watch nope
expect_exit 0 "mentions defaults" -- "$S/watch-conf" slack-mentions
expect_jq "mentions" '.channels == ["#team-app"] and .since == "24h" and .agent == "agent:core:analyst" and .notify == "draft"'
expect_exit 0 "notion defaults" -- "$S/watch-conf" notion-assigned
expect_jq "notion" '.properties == ["Owner"] and .mode == "run" and .exclude_status == ["Done"]'
expect_exit 0 "channel to repos" -- "$S/watch-conf" channel-repos "#app-errors"
expect_jq "channel-repos" '. == ["acme/app"]'
expect_exit 2 "usage" -- "$S/watch-conf" bogus
conf; expect_exit 3 "no config" -- "$S/watch-conf" list; conf "$FIX"

echo "watch-match"
expect_exit 0 "match" -- "$S/watch-match" timeouts "$TMP/msgs.json"
expect_jq "includes (any case) OR regex, within period, max 3 newest scanned" \
  '.scanned == 3 and ([.matched[].id] == ["C1:1", "C1:3"])'
expect_exit 0 "case-sensitive watch" -- "$S/watch-match" exact "$TMP/msgs.json"
expect_jq "nothing matches ERR" '.matched == []'
printf '[{"text": "x"}]' >"$TMP/bad.json"
expect_exit 2 "malformed input refused" -- "$S/watch-match" timeouts "$TMP/bad.json"
expect_exit 0 "stdin input" -- sh -c "\"$S/watch-match\" timeouts < \"$TMP/msgs.json\""
expect_jq "stdin works" '(.matched | length) == 2'

echo "trust and scale"
jq '.slack.watches.timeouts.action.trusted_authors = ["U1"] | .slack.watches.timeouts.action.level = "L2"' \
  "$FIX" >"$TMP/trusted.json"
conf "$TMP/trusted.json"
expect_exit 0 "trusted author keeps the action level" -- "$S/watch-match" timeouts "$TMP/msgs.json" --all
expect_jq "trusted" 'all(.matched[]; .trusted and .action_level == "L2")'
conf "$FIX"
expect_exit 0 "untrusted author drops to L0" -- "$S/watch-match" timeouts "$TMP/msgs.json" --all
expect_jq "untrusted" 'all(.matched[]; (.trusted | not) and .action_level == "L0")'
expect_exit 2 "a watch name cannot be a path" -- "$S/watch-match" "../x" "$TMP/msgs.json"
ids="$(seq 1 6000 | sed 's/^/C9:/' | tr '\n' ' ')"
# shellcheck disable=SC2086  # one id per word on purpose
"$S/watch-seen" mark slack-watch-timeouts $ids >/dev/null
expect_exit 0 "thousands of processed ids do not overflow the command line" -- "$S/watch-match" timeouts "$TMP/msgs.json"
for i in 1 2 3 4 5 6 7 8; do "$S/watch-seen" mark slack-watch-par "P$i" >/dev/null & done; wait
out="$("$S/watch-seen" list slack-watch-par)"
expect_jq "parallel marks are all kept (locked updates)" 'length == 8'

echo "watch-seen"
expect_exit 0 "mark" -- "$S/watch-seen" mark slack-watch-timeouts C1:1
expect_exit 0 "match skips what was processed" -- "$S/watch-match" timeouts "$TMP/msgs.json"
expect_jq "seen moved aside" '[.matched[].id] == ["C1:3"] and .already_seen == ["C1:1"]'
expect_exit 0 "--all ignores the memory" -- "$S/watch-match" timeouts "$TMP/msgs.json" --all
expect_jq "all" '(.matched | length) == 2'
expect_exit 0 "filter" -- "$S/watch-seen" filter slack-watch-timeouts "$TMP/msgs.json"
expect_jq "filter drops seen" '(map(.id) | index("C1:1")) == null and length == 4'
expect_exit 0 "last before touch" -- "$S/watch-seen" last slack-mentions
expect_jq "never run" '. == null'
expect_exit 0 "touch" -- "$S/watch-seen" touch slack-mentions
expect_jq "last run recorded" '.last_run | test("^20")'
expect_exit 2 "bad key refused" -- "$S/watch-seen" list "../etc"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
