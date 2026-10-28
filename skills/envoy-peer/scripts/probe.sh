#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
# probe.sh — which agent kinds can serve as an envoy, and whether they are logged in.
#
#   probe.sh controller          # kind of the agent in this pane (exit 1 if unknown)
#   probe.sh list [--json]       # kinds Herdr supports AND installed AND != controller
#   probe.sh auth <kind>         # prints ready | not-ready | no-probe (exit 1: kind not in kinds.json)
#   probe.sh args <kind>         # full-permission launch args, one per line
#   probe.sh version <kind>      # first line of the CLI's version output
#
# Auth probes are argv arrays from references/kinds.json, run without a shell;
# their output is never printed (some print account emails or masked keys).
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_row() { kind_row "$1" >/dev/null || die "$(kind_missing_msg "$1")"; }

cmd_controller() {
  require_herdr
  local k
  k="$(controller_kind)"
  case "$k" in ""|unknown|null) die "could not detect the agent kind of pane $HERDR_PANE_ID" ;; esac
  echo "$k"
}

cmd_list() {
  require_herdr
  local json=0 ctl k bin path state verified_at verified selectable reason rows="[]"
  [ "${1:-}" = "--json" ] && json=1
  ctl="$(cmd_controller)"
  state="$(state_file)"
  for k in $(herdr_kinds); do
    [ "$k" = "$ctl" ] && continue
    bin="$(kind_field "$k" binary)"
    [ -n "$bin" ] || bin="$k"
    path="$(command -v "$bin" 2>/dev/null || true)"
    [ -n "$path" ] || continue
    verified_at=""
    [ -f "$state" ] && verified_at="$(jq -r --arg k "$k" '.kinds[$k].verified_at // empty' "$state" 2>/dev/null || true)"
    if ! kind_row "$k" >/dev/null; then
      verified=false; selectable=false; reason="not in references/kinds.json"
    elif ! kind_verified "$k"; then
      verified=false; selectable=false; reason="flags not verified in references/kinds.json"
    else
      verified=true; selectable=true; reason=""
    fi
    rows="$(jq -c --arg k "$k" --arg p "$path" --argjson v "$verified" --arg at "$verified_at" \
      --argjson s "$selectable" --arg r "$reason" \
      '. + [{kind: $k, binary_path: $p, verified: $v,
             auth_verified_at: (if $at == "" then null else $at end),
             selectable: $s, reason: (if $r == "" then null else $r end)}]' <<<"$rows")"
  done
  if [ "$json" = 1 ]; then
    jq . <<<"$rows"
  else
    jq -r '.[] | "\(.kind)\t\(if .selectable then "selectable" else "not selectable: \(.reason)" end)\t\(.binary_path)"' <<<"$rows"
  fi
}

cmd_auth() {
  local k="${1:-}" bin out rc=0 rjq
  [ -n "$k" ] || usage_die "auth needs a kind"
  need_row "$k"
  bin="$(kind_field "$k" binary)"
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found on PATH; install $k first"
  if ! jq -e --arg k "$k" '.kinds[$k].auth_probe | type == "array" and length > 0' "$KINDS_FILE" >/dev/null; then
    echo no-probe; return 0
  fi
  local probe=() a
  while IFS= read -r a; do probe+=("$a"); done < <(jq -r --arg k "$k" '.kinds[$k].auth_probe[]' "$KINDS_FILE")
  rjq="$(kind_field "$k" ready_jq)"
  if [ -n "$rjq" ]; then
    out="$(run_bounded 30 "${probe[@]}" </dev/null 2>/dev/null)" || rc=$?
    if [ "$rc" = 0 ] && jq -e "$rjq" >/dev/null 2>&1 <<<"$out"; then echo ready; else echo not-ready; fi
  else
    run_bounded 30 "${probe[@]}" </dev/null >/dev/null 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then echo ready; else echo not-ready; fi
  fi
}

cmd_args() {
  [ -n "${1:-}" ] || usage_die "args needs a kind"
  need_row "$1"
  kind_launch_args "$1"
}

cmd_version() {
  local k="${1:-}" v=() a
  [ -n "$k" ] || usage_die "version needs a kind"
  need_row "$k"
  while IFS= read -r a; do v+=("$a"); done < <(jq -r --arg k "$k" '.kinds[$k].version_cmd[]?' "$KINDS_FILE")
  [ "${#v[@]}" -gt 0 ] || die "kind '$k' has no version_cmd"
  run_bounded 15 "${v[@]}" </dev/null 2>&1 | head -1
}

sub="${1:-}"; shift || true
case "$sub" in
  controller) cmd_controller ;;
  list) cmd_list "$@" ;;
  auth) cmd_auth "$@" ;;
  args) cmd_args "$@" ;;
  version) cmd_version "$@" ;;
  -h|--help) print_usage ;;
  *) print_usage >&2; exit 2 ;;
esac
