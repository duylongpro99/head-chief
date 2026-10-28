#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
# cleanup.sh — close a run's panes, or every abandoned run under an .envoy root.
#
#   cleanup.sh --run DIR
#   cleanup.sh --all [--root DIR] [--yes]
#
# --run stops the envoy, then the reviewer (stop.sh), records final_status (the
# status before cleanup, unless already set) and sets status to cleaned.
# --all scans <root>/runs/*/run.json (root defaults to the .envoy folder of the
# current git toplevel) for runs not yet cleaned. It only touches runs whose
# controller is this pane or a pane that no longer exists; runs of another live
# controller are listed as skipped. Without --yes it is a dry run.
#
# Exit 0: done. 9: a pane did not belong to its run and was left open.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mode="" run="" root="" yes=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run) [ "$#" -ge 2 ] || usage_die "--run needs a folder"; mode=run; run="$2"; shift 2 ;;
    --all) mode=all; shift ;;
    --root) [ "$#" -ge 2 ] || usage_die "--root needs a folder"; root="$2"; shift 2 ;;
    --yes) yes=1; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *) usage_die "unknown argument: $1" ;;
  esac
done
[ -n "$mode" ] || usage_die "pass --run DIR or --all"
require_herdr

closed=0 gone=0 refused=0

# clean_run <dir>: stop both roles and mark the run cleaned.
clean_run() {
  local d="$1" role rc out worst=0
  for role in envoy reviewer; do
    rc=0
    out="$("$SCRIPTS_DIR/stop.sh" --run "$d" --role "$role")" || rc=$?
    case "$rc" in
      0) case "$out" in *"closed pane"*) closed=$((closed + 1)) ;; esac ;;
      10) gone=$((gone + 1)) ;;
      9) refused=$((refused + 1))
         echo "refused: $(run_get "$d" .run_id) $role pane $(run_get "$d" ".$role.pane") does not belong to the run; left open"
         worst=9 ;;
      *) worst="$rc" ;;
    esac
  done
  [ "$worst" = 0 ] || return "$worst"
  run_update "$d" '.final_status = (.final_status // .status) | .status = "cleaned"'
}

if [ "$mode" = run ]; then
  run="$(resolve_run "$run")"
  rc=0; clean_run "$run" || rc=$?
  [ "$rc" = 0 ] || exit "$rc"
  echo "cleaned $(run_get "$run" .run_id): closed $closed pane(s), $gone already gone"
  exit 0
fi

[ -n "$root" ] || root="$(envoy_root "$PWD")"
[ -d "$root/runs" ] || { echo "no runs under $root"; exit 0; }
live=" $(herdr pane list | jq -r '.result.panes[].pane_id' | tr '\n' ' ') "
total=0 skipped=0 picked=0 rc_all=0
for f in "$root"/runs/*/run.json; do
  [ -f "$f" ] || continue
  d="$(cd "$(dirname "$f")" && pwd -P)"
  [ "$(run_get "$d" .status)" != cleaned ] || continue
  total=$((total + 1))
  ctl="$(run_get "$d" .controller.pane)"
  id="$(run_get "$d" .run_id)"
  if [ "$ctl" != "$HERDR_PANE_ID" ] && case "$live" in *" $ctl "*) true ;; *) false ;; esac; then
    skipped=$((skipped + 1))
    echo "skipped $id (controller alive: $ctl)"
    continue
  fi
  picked=$((picked + 1))
  panes="$(jq -r '[.envoy, .reviewer] | map(select(.pane != null and .closed_at == null) | .pane) | join(" ")' "$d/run.json")"
  if [ "$yes" = 1 ]; then
    rc=0; clean_run "$d" || rc=$?
    if [ "$rc" = 0 ]; then echo "cleaned $id (${panes:-no open panes})"; else rc_all="$rc"; fi
  else
    echo "would close $id (status $(run_get "$d" .status); panes: ${panes:-none})"
  fi
done
if [ "$yes" = 1 ]; then
  echo "runs: $total, cleaned: $picked, skipped: $skipped; panes closed: $closed, already gone: $gone, refused: $refused"
else
  echo "dry run: $picked run(s) would be cleaned, $skipped skipped; rerun with --yes to close them"
fi
exit "$rc_all"
