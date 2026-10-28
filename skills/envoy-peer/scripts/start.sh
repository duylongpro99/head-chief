#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
# start.sh — open the pane of a role and start its agent; prints the pane id.
#
#   start.sh --run DIR --role envoy|reviewer
#
# Resume-safe: when run.json already records an open pane of this run (same
# terminal id), no new pane is opened. The envoy's first start records the git
# baseline before its pane opens. Panes open with --no-focus: to the right of the
# controller (envoy), below the envoy (reviewer), or in a new tab (placement tab).
#
# Exit 4: `agent start` failed, the agent is blocked (trust, login or
# onboarding dialog), or a reused pane still runs a program in the foreground
# (agent start would type into it). Prints exactly two lines, the agent status and
# "check pane <id> (label: <label>)"; the pane stays open and its content is
# never read. Exit 11: not ready in time; run start.sh again to resume.
# Exit 10: the pane disappeared.
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

kind="$(run_get "$run" ".$role.kind")"
name="$(run_get "$run" ".$role.name")"
label="$(run_get "$run" ".$role.label")"
model="$(run_get "$run" ".$role.model")"
placement="$(run_get "$run" .placement)"
cwd="$(run_get "$run" .cwd)"
pane="$(run_get "$run" ".$role.pane")"
tid="$(run_get "$run" ".$role.terminal_id")"
closed="$(run_get "$run" ".$role.closed_at")"
kind_row "$kind" >/dev/null || die "$(kind_missing_msg "$kind")"
[ -d "$cwd" ] || die "run cwd is gone: $cwd"

set_role() { run_update "$run" "$1" --arg r "$role" "${@:2}"; }

needs_user() {
  set_role '.[$r].last_status = $s' --arg s "$1"
  echo "$1; agent_status: $(agent_state "$pane")"
  echo "check pane $pane (label: $label)"
  exit 4
}

take_baseline() {
  local top head stash dirty=false
  top="$(git_top "$cwd" || true)"
  if [ -z "$top" ]; then
    run_update "$run" '.baseline.note = "not a git repository: no baseline and no reviewer guard"'
    return 0
  fi
  head="$(git -C "$top" rev-parse -q --verify HEAD 2>/dev/null || true)"
  # The note also marks the baseline as taken, so a reopened envoy pane never retakes it.
  [ -n "$head" ] || run_update "$run" '.baseline.note = "repository has no commits yet: no baseline commit"'
  stash="$(git -C "$top" stash create 2>/dev/null || true)"
  [ -n "$stash" ] || stash="$head"
  git -C "$top" status --short -uall > "$run/baseline-status.txt"
  untracked_manifest "$top" > "$run/baseline-untracked.sha"
  [ -s "$run/baseline-status.txt" ] && dirty=true
  run_update "$run" '.baseline.head = ($h | nn) | .baseline.stash_sha = ($s | nn)
      | .baseline.dirty = $d | .baseline.git_meta_sha = ($m | nn)' \
    --arg h "$head" --arg s "$stash" --argjson d "$dirty" --arg m "$(git_meta_sha "$top")"
}

# True when the pane's shell is the foreground process group (no command, editor or agent running).
at_shell_prompt() {
  herdr pane process-info --pane "$1" 2>/dev/null \
    | jq -e '.result.process_info | .foreground_process_group_id == .shell_pid' >/dev/null 2>&1
}

open_pane() {
  local out="" tab="" ep sel=.result.pane
  if [ "$placement" = tab ]; then
    local ws=()
    [ -z "${HERDR_WORKSPACE_ID:-}" ] || ws=(--workspace "$HERDR_WORKSPACE_ID")
    out="$(herdr tab create ${ws[@]+"${ws[@]}"} --cwd "$cwd" --label "$label" --no-focus 2>&1)" \
      || die "herdr tab create failed: $(herdr_state "$out")"
    sel=.result.root_pane
    tab="$(jq -r '.result.tab.tab_id // empty' <<<"$out")"
  else
    if [ "$role" = reviewer ]; then
      ep="$(run_get "$run" .envoy.pane)"
      if [ -n "$ep" ] && [ -z "$(run_get "$run" .envoy.closed_at)" ] && [ -n "$(pane_row "$ep")" ]; then
        out="$(herdr pane split --pane "$ep" --direction down --cwd "$cwd" --no-focus 2>&1)" || out=""
      fi
      if [ -z "$(jq -r '.result.pane.pane_id // empty' <<<"$out" 2>/dev/null)" ]; then
        out="$(herdr pane split --pane "$HERDR_PANE_ID" --direction down --cwd "$cwd" --no-focus 2>&1)" \
          || die "herdr pane split failed: $(herdr_state "$out")"
      fi
    else
      out="$(herdr pane split --pane "$HERDR_PANE_ID" --direction right --cwd "$cwd" --no-focus 2>&1)" \
        || die "herdr pane split failed: $(herdr_state "$out")"
    fi
  fi
  pane="$(jq -r "$sel.pane_id // empty" <<<"$out")"
  tid="$(jq -r "$sel.terminal_id // empty" <<<"$out")"
  [ -n "$pane" ] || die "Herdr returned no pane id"
  [ -n "$tid" ] || tid="$(pane_row "$pane" | jq -r '.terminal_id // empty')"
  # Without a terminal id the pane could never be proven this run's, so close it while it surely is.
  if [ -z "$tid" ]; then
    herdr pane close "$pane" >/dev/null 2>&1 || true
    die "Herdr returned no terminal id for pane $pane; closed it"
  fi
  # Record ownership before anything else can fail, so cleanup can always find the pane.
  set_role '.[$r].pane = $p | .[$r].tab = ($t | nn) | .[$r].terminal_id = ($tid | nn)
      | .[$r].closed_at = null | .[$r].started_at = null | .[$r].command = null
      | .[$r].prompted_at = null | .[$r].settled_at = null | .[$r].last_status = "opened"' \
    --arg p "$pane" --arg t "$tab" --arg tid "$tid"
  herdr pane rename "$pane" "$label" >/dev/null 2>&1 || echo "$PROG: warning: could not label pane $pane" >&2
}

# 1. Resume an open pane of this run, or forget a pane that is gone.
resumed=0
if [ -n "$pane" ] && [ -z "$closed" ]; then
  row="$(pane_row "$pane")"
  if [ -n "$row" ] && [ "$(jq -r '.terminal_id' <<<"$row")" = "$tid" ]; then
    resumed=1
  else
    set_role '.[$r].closed_at = $_now'
  fi
fi

# 2. Baseline before the envoy's first pane opens.
if [ "$role" = envoy ] && [ "$resumed" = 0 ] \
  && [ -z "$(run_get "$run" .baseline.head)" ] && [ -z "$(run_get "$run" .baseline.note)" ]; then
  take_baseline
fi

# 3. Open the pane.
[ "$resumed" = 1 ] || open_pane

# 4. Start the agent unless this pane already runs it.
if [ "$(herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent // empty' || true)" != "$kind" ]; then
  [ "$resumed" = 0 ] || at_shell_prompt "$pane" || needs_user "pane busy: a program still runs in the foreground"
  other="$(herdr agent get "$name" 2>/dev/null | jq -r '.result.agent.pane_id // empty' || true)"
  [ -z "$other" ] || [ "$other" = "$pane" ] || die "agent name $name is already live in pane $other"
  args=()
  while IFS= read -r a; do args+=("$a"); done < <(kind_launch_args "$kind")
  if [ -n "$model" ]; then
    mflag="$(kind_field "$kind" model_flag)"
    [ -n "$mflag" ] || die "kind '$kind' has no model_flag in $KINDS_FILE"
    args+=("$mflag" "$model")
  fi
  # NUL-separated argv on stdin: jq --args would parse "--flag" values as its own options.
  set_role '.[$r].command = $c' --argjson c "$(printf '%s\0' "$(kind_field "$kind" binary)" ${args[@]+"${args[@]}"} \
    | jq -Rsc 'split("\u0000") | .[:-1]')"
  if ! out="$(herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 -- ${args[@]+"${args[@]}"} 2>&1)"; then
    [ -n "$(pane_row "$pane")" ] || { set_role '.[$r].closed_at = $_now'; echo "pane $pane is gone"; exit 10; }
    needs_user "start-failed ($(herdr_state "$out"))"
  fi
fi

# 5. Wait until the agent is ready (default states idle|done|blocked).
out="$(herdr agent wait "$pane" --timeout 90000 2>&1 || true)"
st="$(herdr_state "$out")"
case "$st" in
  idle|done) ;;
  blocked) needs_user blocked ;;
  timeout)
    set_role '.[$r].last_status = "not-ready"'
    echo "agent in pane $pane (label: $label) not ready after 90 s; run start.sh again to resume"
    exit 11 ;;
  agent_not_found)
    [ -n "$(pane_row "$pane")" ] || { set_role '.[$r].closed_at = $_now'; echo "pane $pane is gone"; exit 10; }
    needs_user "agent exited" ;;
  *) die "unexpected answer from herdr agent wait: $st" ;;
esac

set_role '.[$r].started_at = (.[$r].started_at // $_now) | .[$r].last_status = $s
    | .status = (if $r == "reviewer" then "reviewing" elif .status == "created" then "dispatched" else .status end)' \
  --arg s "$st"
echo "$pane"
