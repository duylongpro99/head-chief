#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
# state.sh — global envoy-peer state at ${XDG_CONFIG_HOME:-~/.config}/envoy-peer/state.json.
# Holds which kinds were verified (time, version, how) and preferences. Never credentials.
#
#   state.sh show
#   state.sh get <kind>                                   # prints verified_at; exit 1 if never verified
#   state.sh set-verified <kind> [--version V] [--probe auth|smoke]
#   state.sh clear <kind>
#   state.sh pref get <key>
#   state.sh pref set <key> <value>                       # value parsed as JSON when valid, else string
#
# Pref keys: default_kind reviewer_kind max_rounds timeout_minutes placement model
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tools jq

STATE="$(state_file)"
LOCK="$STATE.lock"
INIT='{"version":1,"kinds":{},"prefs":{"default_kind":null,"reviewer_kind":null,"max_rounds":3,"timeout_minutes":60,"placement":"split","model":{}}}'
PREF_KEYS=" default_kind reviewer_kind max_rounds timeout_minutes placement model "

ensure_state() {
  [ -f "$STATE" ] && return 0
  mkdir -p "$(dirname "$STATE")"
  printf '%s\n' "$INIT" | jq . | json_write_atomic "$STATE"
}

# Apply a jq filter to the state file in place, under the lock.
_apply() { local f="$1"; shift; jq "$@" "$f" "$STATE" | json_write_atomic "$STATE"; }
update() { with_lock "$LOCK" _apply "$@"; }

read_state() { if [ -f "$STATE" ]; then cat "$STATE"; else printf '%s\n' "$INIT" | jq .; fi; }

sub="${1:-}"; shift || true
case "$sub" in
  show)
    read_state
    ;;
  get)
    k="${1:-}"; [ -n "$k" ] || usage_die "get needs a kind"
    read_state | jq -re --arg k "$k" '.kinds[$k].verified_at // empty' || exit 1
    ;;
  set-verified)
    k="${1:-}"; [ -n "$k" ] || usage_die "set-verified needs a kind"; shift
    ver=""; how="auth"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --version) [ "$#" -ge 2 ] || usage_die "--version needs a value"; ver="$2"; shift 2 ;;
        --probe) [ "$#" -ge 2 ] || usage_die "--probe needs auth|smoke"; how="$2"; shift 2 ;;
        *) usage_die "unknown argument: $1" ;;
      esac
    done
    case "$how" in auth|smoke) ;; *) usage_die "--probe must be auth or smoke" ;; esac
    ensure_state
    update '.kinds[$k] = {verified_at: $at, version: (if $v == "" then null else $v end), probe: $how}' \
      --arg k "$k" --arg at "$(now_iso)" --arg v "$ver" --arg how "$how"
    echo "verified $k"
    ;;
  clear)
    k="${1:-}"; [ -n "$k" ] || usage_die "clear needs a kind"
    ensure_state
    update 'del(.kinds[$k])' --arg k "$k"
    echo "cleared $k"
    ;;
  pref)
    op="${1:-}"; key="${2:-}"
    [ -n "$key" ] || usage_die "pref needs get|set and a key"
    case "$PREF_KEYS" in *" $key "*) ;; *) usage_die "unknown pref key '$key' (one of:$PREF_KEYS)" ;; esac
    case "$op" in
      get)
        read_state | jq -r --arg k "$key" '.prefs[$k] | if . == null then empty elif type == "object" or type == "array" then tojson else . end'
        ;;
      set)
        [ "$#" -ge 3 ] || usage_die "pref set needs a value"
        val="$3"
        ensure_state
        if jq -e . >/dev/null 2>&1 <<<"$val"; then
          update '.prefs[$k] = $v' --arg k "$key" --argjson v "$val"
        else
          update '.prefs[$k] = $v' --arg k "$key" --arg v "$val"
        fi
        echo "set $key"
        ;;
      *) usage_die "pref needs get or set" ;;
    esac
    ;;
  -h|--help) print_usage ;;
  *) print_usage >&2; exit 2 ;;
esac
