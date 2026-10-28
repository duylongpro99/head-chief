#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
# new-run.sh — create a run folder and its run.json, then print the run folder.
#
#   new-run.sh <slug> [--kind K] [--reviewer K] [--max-rounds N] [--timeout-min N]
#              [--placement split|tab] [--model M] [--reviewer-model M] [--cwd DIR]
#
# Defaults come from `state.sh pref get` (default_kind, reviewer_kind, max_rounds,
# timeout_minutes, placement, model.<kind>); flags override them. The reviewer
# defaults to the controller's kind. --cwd defaults to $PWD: pass it explicitly
# when the host shell may have changed folders. The run lives under
# <git toplevel of --cwd>/.envoy/runs/ (see references/run-contract.md).
#
# Exit 1: envoy kind equals the controller's kind, is not installed, not
# supported by Herdr, or has no verified row in references/kinds.json; the
# reviewer kind has no launch args there. Exit 2: usage.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

slug="" kind="" reviewer="" max_rounds="" timeout_min="" placement="" model="" rmodel="" cwd="$PWD"
need_val() { [ "$#" -ge 2 ] && [ -n "$2" ] || usage_die "$1 needs a value"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --kind) need_val "$@"; kind="$2"; shift 2 ;;
    --reviewer) need_val "$@"; reviewer="$2"; shift 2 ;;
    --max-rounds) need_val "$@"; max_rounds="$2"; shift 2 ;;
    --timeout-min) need_val "$@"; timeout_min="$2"; shift 2 ;;
    --placement) need_val "$@"; placement="$2"; shift 2 ;;
    --model) need_val "$@"; model="$2"; shift 2 ;;
    --reviewer-model) need_val "$@"; rmodel="$2"; shift 2 ;;
    --cwd) need_val "$@"; cwd="$2"; shift 2 ;;
    -h|--help) print_usage; exit 0 ;;
    -*) usage_die "unknown flag: $1" ;;
    *) [ -z "$slug" ] || usage_die "only one slug is allowed"; slug="$1"; shift ;;
  esac
done

require_herdr
pref() { "$SCRIPTS_DIR/state.sh" pref get "$1"; }
pref_model() {
  "$SCRIPTS_DIR/state.sh" pref get model \
    | jq -r --arg k "$1" 'if type == "object" then .[$k] // empty else empty end' 2>/dev/null || true
}
posint() { case "$2" in ''|*[!0-9]*|0) usage_die "$1 must be a positive integer" ;; esac; }

slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-24 | sed -E 's/-+$//')"
[ -n "$slug" ] || usage_die "a slug with at least one letter or digit is required"

[ -n "$kind" ] || kind="$(pref default_kind)"
[ -n "$kind" ] || usage_die "no envoy kind: pass --kind (options: probe.sh list)"
[ -n "$max_rounds" ] || max_rounds="$(pref max_rounds)"; [ -n "$max_rounds" ] || max_rounds=3
[ -n "$timeout_min" ] || timeout_min="$(pref timeout_minutes)"; [ -n "$timeout_min" ] || timeout_min=60
[ -n "$placement" ] || placement="$(pref placement)"; [ -n "$placement" ] || placement="split"
posint --max-rounds "$max_rounds"
posint --timeout-min "$timeout_min"
case "$placement" in split|tab) ;; *) usage_die "--placement must be split or tab" ;; esac
[ -d "$cwd" ] || die "--cwd is not a folder: $cwd"
cwd="$(cd "$cwd" && pwd -P)"

ctl_pane="$HERDR_PANE_ID"
ctl_kind="$("$SCRIPTS_DIR/probe.sh" controller)"

# Envoy: a different kind than the controller, installed, Herdr-supported, verified.
[ "$kind" != "$ctl_kind" ] || die "envoy kind '$kind' is the controller's own kind; pick another kind (probe.sh list)"
row="$("$SCRIPTS_DIR/probe.sh" list --json | jq -c --arg k "$kind" '.[] | select(.kind == $k)')"
if [ -z "$row" ]; then
  case " $(herdr_kinds | tr '\n' ' ') " in *" $kind "*) ;; *) die "Herdr does not support agent kind '$kind'" ;; esac
  bin="$(kind_field "$kind" binary)"
  die "'${bin:-$kind}' is not installed; install $kind first (envoy-peer never picks a substitute)"
fi
if ! jq -e '.selectable' >/dev/null <<<"$row"; then
  kind_row "$kind" >/dev/null || die "$(kind_missing_msg "$kind")"
  die "kind '$kind' is not selectable: $(jq -r '.reason' <<<"$row")"
fi

# Reviewer: defaults to the controller's kind; still needs a row with launch args.
[ -n "$reviewer" ] || reviewer="$(pref reviewer_kind)"
[ -n "$reviewer" ] || reviewer="$ctl_kind"
kind_row "$reviewer" >/dev/null || die "$(kind_missing_msg "$reviewer")"
jq -e --arg k "$reviewer" '.kinds[$k].launch_args | length > 0' "$KINDS_FILE" >/dev/null \
  || die "reviewer kind '$reviewer' has no verified launch args in $KINDS_FILE"
rbin="$(kind_field "$reviewer" binary)"
command -v "${rbin:-$reviewer}" >/dev/null 2>&1 || die "'${rbin:-$reviewer}' is not installed; install $reviewer or pick another --reviewer"

[ -n "$model" ] || model="$(pref_model "$kind")"
[ -n "$rmodel" ] || rmodel="$(pref_model "$reviewer")"

root="$(envoy_root "$cwd")"
mkdir -p "$root/runs"
[ -f "$root/.gitignore" ] || printf '*\n' > "$root/.gitignore"
nonce="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
[ "${#nonce}" = 6 ] || die "could not read a nonce from /dev/urandom"
id="$(date +%y%m%d-%H%M)-$slug-$nonce"
dir="$root/runs/$id"
mkdir "$dir" 2>/dev/null || die "run folder already exists or cannot be created: $dir"

ename="env-$kind-$nonce"
rname="rev-$reviewer-$nonce"
for n in "$ename" "$rname"; do
  printf '%s' "$n" | grep -Eq '^[a-z0-9][a-z0-9-]{0,31}$' || die "agent name '$n' is not 1-32 chars of [a-z0-9-]"
done

jq -n --arg id "$id" --arg nonce "$nonce" --arg dir "$dir" --arg cwd "$cwd" --arg now "$(now_iso)" \
  --arg cp "$ctl_pane" --arg ck "$ctl_kind" \
  --arg ek "$kind" --arg en "$ename" --arg el "envoy $kind $slug" --arg em "$model" \
  --arg rk "$reviewer" --arg rn "$rname" --arg rl "reviewer $reviewer $slug" --arg rm "$rmodel" \
  --argjson mr "$max_rounds" --argjson tm "$timeout_min" --arg pl "$placement" '
  def nn: if . == "" then null else . end;
  def role($k; $n; $l; $m): {kind: $k, name: $n, label: $l, model: ($m | nn),
    pane: null, tab: null, terminal_id: null, command: null,
    started_at: null, prompted_at: null, settled_at: null, last_status: null, closed_at: null};
  {version: 1, run_id: $id, nonce: $nonce, run_dir: $dir, cwd: $cwd, created_at: $now,
   controller: {pane: $cp, kind: $ck},
   envoy: role($ek; $en; $el; $em),
   reviewer: role($rk; $rn; $rl; $rm),
   baseline: {head: null, stash_sha: null, dirty: null, status_file: "baseline-status.txt",
              untracked_manifest: "baseline-untracked.sha", git_meta_sha: null, note: null},
   guard: {}, round: 0, max_rounds: $mr, timeout_minutes: $tm, placement: $pl,
   dispatched_at: null, status: "created", final_status: null, updated_at: $now}' \
  | json_write_atomic "$dir/run.json"

echo "$dir"
