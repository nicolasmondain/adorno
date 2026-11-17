#!/usr/bin/env bash
# Tests for the journal viewer (viewer/): what can be checked without a browser, then a keyboard-driven smoke test in
# Chromium (tests/journal-viewer.smoke.py, Playwright) against `kit serve` and synthetic journals.
# No browser on this machine → the smoke test is SKIPPED, visibly (ADORNO_REQUIRE_BROWSER=1 makes that a failure: CI).
# To get the browser once: uv run --script tests/journal-viewer.smoke.py --install
# Usage: tests/journal-viewer.test.sh   (the screenshot goes to $ADORNO_SCREENSHOT, default a temp file that is removed)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; SERVER=""
stop_server() { [ -z "$SERVER" ] || { kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null; }; }
trap 'stop_server; rm -rf "$TMP"' EXIT
if python3 -c 'import yaml' 2>/dev/null; then KIT=(python3 "$ROOT/bin/kit")
elif command -v uv >/dev/null 2>&1; then KIT=("$ROOT/bin/kit")
else echo "needs python3 with PyYAML, or uv" >&2; exit 1; fi

pass=0 fail=0 skip=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }

echo "the viewer's files"
V="$ROOT/viewer"
for f in index.html tokens.css viewer.css app.js model.js diagram.js ui.js dom.js; do
  [ -s "$V/$f" ] && ok "viewer/$f" || ko "viewer/$f is missing"
done
found="$(grep -n -E '#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(' "$V"/viewer.css "$V"/*.js "$V"/index.html | grep -v 'location.hash' || true)"
[ -z "$found" ] && ok "colours are written in tokens.css only" || ko "a colour outside tokens.css" "$found"
found="$(grep -n -E "font-family|font:" "$V"/viewer.css | grep -v 'var(--font' | grep -v 'font: inherit' || true)"
[ -z "$found" ] && ok "fonts are named in tokens.css only" || ko "a font outside tokens.css" "$found"
found="$(grep -n -E 'https?://' "$V"/*.html "$V"/*.css "$V"/*.js | grep -v 'www.w3.org/2000/svg' || true)"
[ -z "$found" ] && ok "nothing is loaded from elsewhere" || ko "an outside address in the viewer" "$found"
found="$(grep -n -E 'innerHTML|outerHTML|insertAdjacentHTML|document\.write|\beval\(' "$V"/*.js || true)"
[ -z "$found" ] && ok "what a journal holds is never parsed as markup" || ko "markup built from text" "$found"
found="$(grep -n -E '<script(>| [^>]*[^c]>)|<style|\son[a-z]+=|\sstyle=' "$V"/index.html | grep -v 'src="app.js"' || true)"
[ -z "$found" ] && ok "no inline script nor style: the content policy holds" || ko "inline script or style" "$found"

echo "the journals"
RUNS="$TMP/runs"; FIX="$ROOT/tests/fixtures/journal"
F1=feature-build-20260101T100000-1000-1; F2=pr-review-20260101T120000-1001-2; F3=broken-20260101T130000-1002-3
LARGE=feature-build-20260102T090000-2000-9
mkdir -p "$RUNS/$LARGE"
for d in "$F1" "$F2" "$F3"; do
  cp -R "$FIX/$d" "$RUNS/$d"
  for f in "$RUNS/$d"/*.jsonl; do sed -e "s|__RUNS__|$RUNS|g" -e "s|__ROOT__|$TMP|g" "$f" >"$f.tmp" && mv "$f.tmp" "$f"; done
done
python3 "$FIX/gen-large.py" 10000 >"$RUNS/$LARGE/events.jsonl"
[ "$(wc -l <"$RUNS/$LARGE/events.jsonl")" -gt 9000 ] && ok "a large synthetic journal (thousands of events, 30 agents)" || ko "large journal"
python3 "$ROOT/src/skills/adorno-journal/scripts/journal.py" validate "$RUNS/$LARGE/events.jsonl" >"$TMP/invalid" 2>&1 \
  && ok "... valid against the schema" || ko "the large journal is not valid" "$(head -3 "$TMP/invalid")"

"${KIT[@]}" serve --port 0 --runs "$RUNS" >"$TMP/url" 2>"$TMP/serve.err" & SERVER=$!
tries=0; until [ -s "$TMP/url" ] || [ "$tries" -ge 300 ]; do tries=$((tries + 1)); sleep 0.1; done
URL="$(head -n 1 "$TMP/url" | sed 's|/$||')"
[ -n "$URL" ] && ok "kit serve serves the viewer" || ko "kit serve did not start" "$(cat "$TMP/serve.err")"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$URL/")" = 200 ] && [ "$(curl -s -o /dev/null -w '%{http_code}' "$URL/app.js")" = 200 ] \
  && ok "the page and its scripts are there" || ko "the viewer is not served"
start="$(python3 -c 'import time; print(int(time.time() * 1000))')"
curl -s "$URL/api/runs/$LARGE" -o "$TMP/large.json"
took=$(( $(python3 -c 'import time; print(int(time.time() * 1000))') - start ))
[ "$(jq '.events | length' "$TMP/large.json")" -gt 9000 ] && ok "the large run is normalized (${took} ms)" || ko "large run not read"

echo "in a browser"
SHOT="${ADORNO_SCREENSHOT:-$TMP/viewer.png}"
if command -v uv >/dev/null 2>&1; then
  uv run --offline --script "$ROOT/tests/journal-viewer.smoke.py" "$URL" "$F1" "$F2" "$LARGE" "$SHOT" >"$TMP/smoke.out" 2>"$TMP/smoke.err"; rc=$?
  cat "$TMP/smoke.out"
  # uv could not even start the script (Playwright is not in its cache, and nothing is downloaded here): no browser.
  # Any other failure, a script that crashes before its first check included, is a failure.
  if [ "$rc" != 0 ] && [ "$rc" != 77 ] && grep -q 'No solution found when resolving script dependencies' "$TMP/smoke.err"; then rc=77; fi
else
  rc=77; echo "uv is not installed" >"$TMP/smoke.err"
fi
case "$rc" in
  0) ok "the browser smoke test passed (screenshot: $SHOT)" ;;
  77)
    if [ "${ADORNO_REQUIRE_BROWSER:-0}" = 1 ]; then
      ko "no browser, and ADORNO_REQUIRE_BROWSER=1" "$(tail -n 3 "$TMP/smoke.err")"
    else
      skip=1
      printf '  SKIP the browser smoke test: no Playwright browser here (%s)\n' "$(tail -n 1 "$TMP/smoke.err")"
      printf '       run once: uv run --script tests/journal-viewer.smoke.py --install\n'
      [ -z "${GITHUB_ACTIONS:-}" ] || echo "::warning title=viewer smoke test skipped::no Playwright browser on this runner: the viewer was not opened in a browser"
    fi ;;
  *) ko "the browser smoke test failed" "$(tail -n 12 "$TMP/smoke.err")" ;;
esac

echo
echo "$pass passed, $fail failed$([ "$skip" = 0 ] || echo ", 1 skipped")"
[ "$fail" -eq 0 ]
