# shellcheck shell=bash
# Shared helpers for adorno-watch scripts. Sourced, never executed. macOS bash 3.2 compatible.
set -euo pipefail

WATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${ADORNO_CONF:-$WATCH_DIR/../adorno.json}"
SELF="$(basename "$0")"
E_USAGE=2 E_UNCONFIGURED=3

die() { printf '%s: %s\n' "$SELF" "$1" >&2; exit "${2:-1}"; }
command -v jq >/dev/null 2>&1 || die "missing dependency: jq"
[ -f "$CONF" ] || die "config not found: $CONF (install adorno with your personal layer, or set ADORNO_CONF)" "$E_UNCONFIGURED"

state_dir() { local d="${ADORNO_HOME:-$HOME/.adorno}/state"; mkdir -p "$d"; printf '%s' "$d"; }
valid_key() { [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid state key '$1'" "$E_USAGE"; }

# since_epoch 24h|90m|7d|2026-11-01[T..Z] -> epoch seconds (relative to now, or absolute)
since_epoch() {
  jq -nr --arg s "$1" '
    if ($s | test("^[0-9]+[mhd]$")) then
      now - (($s[:-1] | tonumber) * ({"m": 60, "h": 3600, "d": 86400}[$s[-1:]]))
    elif ($s | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) then ($s + "T00:00:00Z" | fromdateiso8601)
    elif ($s | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) then ($s | sub("(\\.[0-9]+)?Z?$"; "Z") | fromdateiso8601)
    else error("since: expected 90m, 24h, 7d or a date, got \($s)") end | floor'
}
