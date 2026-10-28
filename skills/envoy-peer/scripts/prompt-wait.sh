#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
# prompt-wait.sh — send one line to a role's agent and wait, bounded, until it settles.
#
#   prompt-wait.sh --run DIR --role envoy|reviewer [--text "one line"] [--round N]
#                  [--expect FILE --match REGEX] [--wait-ms N] [--no-read]
#
# Waits at most --wait-ms (default 540000, clamped to 570000), then exits 3.
# The caller's tool timeout must be at least wait-ms + 30000: in Claude Code
# pass `timeout: 600000` to the Bash tool, or run the call in the background.
# Without --text it only waits for the outstanding turn. Settled = idle or done.
#
# With --expect/--match, a settled turn also needs FILE modified after the turn,
# a "Round: N" line when --round is given, and exactly one line matching REGEX;
# only that validated line is printed. Otherwise exit 7 and one line
# "missing|stale|no-round|no-match: FILE".
#
# Exit codes: 0 settled, 3 still running, 4 blocked (needs the user), 5 run
# timeout, 6 prompt stalled, 7 expected file invalid, 8 refused duplicate
# --text, 10 pane or agent gone. On 4 and 6 the last pane lines are shown on
# stderr through redact; --no-read shows only the agent status and pane id.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run="" role="" text="" has_text=0 round="" expect="" match="" wait_ms=540000 no_read=0
need_val() { [ "$#" -ge 2 ] || usage_die "$1 needs a value"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run) need_val "$@"; run="$2"; shift 2 ;;
    --role) need_val "$@"; role="$2"; shift 2 ;;
    --text) need_val "$@"; text="$2"; has_text=1; shift 2 ;;
    --round) need_val "$@"; round="$2"; shift 2 ;;
    --expect) need_val "$@"; expect="$2"; shift 2 ;;
    --match) need_val "$@"; match="$2"; shift 2 ;;
    --wait-ms) need_val "$@"; wait_ms="$2"; shift 2 ;;
    --no-read) no_read=1; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *) usage_die "unknown argument: $1" ;;
  esac
done
case "$role" in envoy|reviewer) ;; *) usage_die "--role must be envoy or reviewer" ;; esac
case "$wait_ms" in ''|*[!0-9]*) usage_die "--wait-ms must be milliseconds" ;; esac
case "$round" in ''|*[!0-9]*) [ -z "$round" ] || usage_die "--round must be a number" ;; esac
{ [ -n "$expect" ] && [ -n "$match" ]; } || { [ -z "$expect" ] && [ -z "$match" ]; } \
  || usage_die "--expect and --match go together"
if [ "$has_text" = 1 ]; then
  [ -n "$text" ] || usage_die "--text is empty"
  case "$text" in *$'\n'*|*$'\r'*) usage_die "--text must be one line" ;; esac
fi
[ "$wait_ms" -le 570000 ] || wait_ms=570000
[ "$wait_ms" -ge 1000 ] || wait_ms=1000
run="$(resolve_run "$run")"
require_herdr

pane="$(run_get "$run" ".$role.pane")"
label="$(run_get "$run" ".$role.label")"
prompted="$(run_get "$run" ".$role.prompted_at")"
settled_before="$(run_get "$run" ".$role.settled_at")"
outstanding=0
[ -n "$prompted" ] && [ -z "$settled_before" ] && outstanding=1
t0="$(now_epoch)"

set_role() { run_update "$run" "$1" --arg r "$role" "${@:2}"; }
remaining() { local left=$(( wait_ms - ($(now_epoch) - t0) * 1000 )); [ "$left" -ge 1000 ] || left=1000; echo "$left"; }

gone() {
  [ -n "$(pane_row "$pane")" ] || set_role '.[$r].closed_at = (.[$r].closed_at // $_now)'
  set_role '.[$r].last_status = "gone"'
  echo "gone: the $role agent in pane $pane is no longer running"
  exit 10
}

# Last pane lines on stderr, always through redact; --no-read shows status only.
show_tail() {
  if [ "$no_read" = 1 ]; then
    echo "agent_status: $(agent_state "$pane") pane $pane" >&2
  else
    herdr agent read "$pane" --source recent-unwrapped --lines "$1" 2>/dev/null | redact >&2 || true
  fi
}

# $1 tells the caller how to resume: whether the --text of this call was sent.
blocked() {
  set_role '.[$r].last_status = "blocked"'
  echo "blocked: check pane $pane (label: $label); ${1:-call again without --text}"
  show_tail 40
  exit 4
}

not_settled() {
  local over
  set_role '.[$r].last_status = "working"'
  over="$(jq -r '(.dispatched_at // empty) as $d | if $d == null then "no"
      elif (now - ($d | fromdateiso8601)) > (.timeout_minutes * 60) then "yes" else "no" end' "$run/run.json")"
  if [ "$over" = yes ]; then
    run_update "$run" '.status = "timeout"'
    echo "timeout: the run passed its $(run_get "$run" .timeout_minutes) minute limit; pane $pane is still open"
    exit 5
  fi
  echo "still running: pane $pane; $1"
  exit 3
}

expect_fail() { echo "$1: $expect"; exit 7; }

check_expect() {
  local m ref n
  [ -f "$expect" ] || expect_fail missing
  m="$(file_mtime "$expect")"
  if [ "$outstanding" = 1 ]; then
    ref="$(iso_to_epoch "$prompted")"
    [ "$m" -ge "$ref" ] || expect_fail stale
  else
    # Nothing outstanding: the file must have changed after the last settled turn.
    [ -n "$settled_before" ] || expect_fail stale
    ref="$(iso_to_epoch "$settled_before")"
    [ "$m" -gt "$ref" ] || expect_fail stale
  fi
  if [ -n "$round" ]; then
    grep -Eq "^Round: ${round}[[:space:]]*\$" "$expect" || expect_fail no-round
  fi
  n="$(grep -Ec -- "$match" "$expect" || true)"
  [ "$n" = 1 ] || expect_fail no-match
  grep -E -- "$match" "$expect"
}

[ -n "$pane" ] && [ -z "$(run_get "$run" ".$role.closed_at")" ] || { echo "gone: no open $role pane in this run"; exit 10; }
st="$(agent_state "$pane")"
[ "$st" != agent_not_found ] || gone

if [ "$has_text" = 1 ]; then
  if [ "$outstanding" = 1 ] && [ "$st" = working ]; then
    echo "refused: the $role is still working on the prompt sent at $prompted; call again without --text"
    exit 8
  fi
  [ "$st" != blocked ] || blocked "nothing was sent; call again with the same --text"
  if [ "$st" = working ]; then
    # Busy with a turn this run did not send: let it finish before sending.
    out="$(herdr agent wait "$pane" --timeout "$wait_ms" 2>&1 || true)"
    st="$(herdr_state "$out")"
    case "$st" in
      idle|done) ;;
      blocked) blocked "nothing was sent; call again with the same --text" ;;
      timeout) not_settled "nothing was sent (the agent was busy); call again with the same --text" ;;
      agent_not_found) gone ;;
      *) die "unexpected answer from herdr agent wait: $st" ;;
    esac
  fi
  prompted="$(now_iso)"
  set_role '.[$r].prompted_at = $p | .[$r].settled_at = null | .[$r].last_status = "prompted"
      | (if $r == "envoy" and .dispatched_at == null then .dispatched_at = $p else . end)
      | (if $n == "" then . else .round = ($n | tonumber) end)' \
    --arg p "$prompted" --arg n "$round"
  outstanding=1
  # Success prints the agent object; failure prints {"error":{"code":...}} on stderr.
  out="$(herdr agent prompt "$pane" "$text" --wait --timeout "$(remaining)" 2>&1 || true)"
  st="$(herdr_state "$out")"
  if [ "$st" = agent_prompt_stalled ]; then
    st="$(agent_state "$pane")"
    case "$st" in
      working)
        out="$(herdr agent wait "$pane" --timeout "$(remaining)" 2>&1 || true)"
        st="$(herdr_state "$out")" ;;
      idle|done)
        set_role '.[$r].last_status = "stalled"'
        echo "stalled: the $role in pane $pane did not start working on the prompt (agent_status: $st)"
        show_tail 20
        exit 6 ;;
    esac
  fi
else
  out="$(herdr agent wait "$pane" --timeout "$wait_ms" 2>&1 || true)"
  st="$(herdr_state "$out")"
fi

case "$st" in
  idle|done) ;;
  blocked) blocked ;;
  timeout) not_settled "call prompt-wait.sh again without --text" ;;
  agent_not_found) gone ;;
  *) die "unexpected answer from herdr: $st" ;;
esac

if [ "$outstanding" = 1 ]; then
  set_role '.[$r].settled_at = $_now | .[$r].last_status = $s' --arg s "$st"
else
  set_role '.[$r].last_status = $s' --arg s "$st"
fi
[ -z "$expect" ] || check_expect
exit 0
