#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
# stop.sh — close the pane of one role, only when it still belongs to this run.
#
#   stop.sh --run DIR --role envoy|reviewer
#
# Ownership = the pane id AND terminal id recorded by start.sh. `herdr pane close`
# ends the agent; no per-kind exit command is sent. Foreground processes are
# recorded first; any that outlive the pane in the run's folder are reported
# as survivors, never killed.
#
# Exit 0: closed, or nothing to close. 9: the pane is not this run's (left open).
# 10: the pane was already gone (closed_at recorded).
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

run="" role=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run) [ "$#" -ge 2 ] || usage_die "--run needs a folder"; run="$2"; shift 2 ;;
    --role) [ "$#" -ge 2 ] || usage_die "--role needs envoy|reviewer"; role="$2"; shift 2 ;;
    -h|--help) print_usage; exit 0 ;;
    *) usage_die "unknown argument: $1" ;;
  esac
done
case "$role" in envoy|reviewer) ;; *) usage_die "--role must be envoy or reviewer" ;; esac
run="$(resolve_run "$run")"
require_herdr

pane="$(run_get "$run" ".$role.pane")"
tid="$(run_get "$run" ".$role.terminal_id")"
cwd="$(run_get "$run" .cwd)"
set_role() { run_update "$run" "$1" --arg r "$role" "${@:2}"; }

if [ -z "$pane" ] || [ -n "$(run_get "$run" ".$role.closed_at")" ]; then
  echo "$role: nothing to close"
  exit 0
fi
row="$(pane_row "$pane")"
if [ -z "$row" ]; then
  set_role '.[$r].closed_at = $_now'
  echo "$role: pane $pane already gone"
  exit 10
fi
if [ -z "$tid" ] || [ "$(jq -r '.terminal_id' <<<"$row")" != "$tid" ]; then
  echo "$role: refused, pane $pane does not belong to this run (terminal id differs)"
  exit 9
fi

procs="$(herdr pane process-info --pane "$pane" 2>/dev/null \
  | jq -c '[.result.process_info.foreground_processes[]?
            | {pid, cwd, command: ((.cmdline // "") | split(" ")[0] | split("/")[-1])}]' 2>/dev/null || echo '[]')"
[ -n "$procs" ] || procs='[]'
set_role '.[$r].processes_at_stop = $p' --argjson p "$procs"

herdr pane close "$pane" >/dev/null 2>&1 || {
  [ -z "$(pane_row "$pane")" ] || die "herdr pane close $pane failed"
}
set_role '.[$r].closed_at = $_now'
echo "$role: closed pane $pane"

# Report processes from this run's folder that outlived their pane.
pids="$(jq -r --arg c "$cwd" '.[] | select(.cwd == $c or (.cwd // "" | startswith($c + "/"))) | .pid' <<<"$procs")"
if [ -n "$pids" ]; then
  sleep 1
  # shellcheck disable=SC2086  # pids is a newline-separated list of numbers
  alive="$(ps -o pid=,comm= -p "$(echo $pids | tr ' ' ',')" 2>/dev/null || true)"
  if [ -n "$alive" ]; then
    echo "$PROG: survivors (not killed; stop them yourself if they are not wanted):" >&2
    printf '%s\n' "$alive" | sed 's/^ */  pid /' >&2
  fi
fi
exit 0
