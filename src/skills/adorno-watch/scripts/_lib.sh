# shellcheck shell=bash
# shellcheck disable=SC2034  # WATCH_DIR and the exit codes are read by the scripts that source this file
# Shared helpers for adorno-watch scripts. Sourced, never executed. macOS bash 3.2 compatible.
set -euo pipefail

WATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(basename "$0")"
E_USAGE=2 E_UNCONFIGURED=3
# Your settings: the registry `bin/kit install` writes outside every repo (tests run with a throwaway HOME).
CONF="$HOME/.adorno/registry.json"

die() { printf '%s: %s\n' "$SELF" "$1" >&2; exit "${2:-1}"; }
command -v jq >/dev/null 2>&1 || die "missing dependency: jq"
[ -f "$CONF" ] || die "your settings are not installed ($CONF): run bin/kit install with your personal layer" "$E_UNCONFIGURED"

state_dir() { local d="$HOME/.adorno/state"; mkdir -p "$d"; printf '%s' "$d"; }
valid_key() { [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid name '$1' (letters, digits, . _ -)" "$E_USAGE"; }

# locked_update FILE JQ_ARGS… — read-modify-write of a state file under a lock, through a private temp file
locked_update() {
  local f="$1" lock tries=0; shift
  lock="$f.lock"
  until mkdir "$lock" 2>/dev/null; do
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then rm -rf "$lock"; continue; fi
    tries=$((tries + 1)); [ "$tries" -lt 300 ] || die "timed out waiting for $lock"
    sleep 0.1
  done
  local tmp="$f.$$.tmp" rc=0
  jq "$@" <"$f" >"$tmp" && mv "$tmp" "$f" || rc=$?
  rm -f "$tmp"; rm -rf "$lock"
  return "$rc"
}

# since_epoch 24h|90m|7d|2026-11-01[T..Z] -> epoch seconds (relative to now, or absolute)
since_epoch() {
  jq -nr --arg s "$1" '
    if ($s | test("^[0-9]+[mhd]$")) then
      now - (($s[:-1] | tonumber) * ({"m": 60, "h": 3600, "d": 86400}[$s[-1:]]))
    elif ($s | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) then ($s + "T00:00:00Z" | fromdateiso8601)
    elif ($s | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) then ($s | sub("(\\.[0-9]+)?Z?$"; "Z") | fromdateiso8601)
    else error("since: expected 90m, 24h, 7d or a date, got \($s)") end | floor'
}
