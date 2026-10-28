#!/usr/bin/env bash
# shellcheck disable=SC2034  # SCRIPTS_DIR and KINDS_FILE are read by the scripts that source this file
# lib.sh — shared helpers for the envoy-peer scripts. Source it; do not run it.
# Targets bash 3.2 (macOS): no associative arrays, no mapfile, no `date -d`,
# no timeout(1). Empty arrays under `set -u` use ${a[@]+"${a[@]}"}.

PROG="$(basename "$0")"
# Run folders, manifests and state can hold peer output: every file the scripts write is private.
umask 077

die() { echo "$PROG: $*" >&2; exit 1; }
usage_die() { echo "$PROG: $*" >&2; exit 2; }
# Print the calling script's header comment (from line 2 up to `set -euo pipefail`).
print_usage() { sed -n '2,/^set -e/p' "$0" | sed -e '/^# shellcheck/d' -e '/^set -e/d' -e 's/^# \{0,1\}//'; }

# Resolve the skill folder through one level of symlink on the sourced file;
# `pwd -P` resolves a symlinked skill folder (install.sh links the folder).
_lib_src="${BASH_SOURCE[0]}"
if [ -L "$_lib_src" ]; then
  _lib_t="$(readlink "$_lib_src")"
  case "$_lib_t" in /*) _lib_src="$_lib_t" ;; *) _lib_src="$(dirname "$_lib_src")/$_lib_t" ;; esac
fi
SKILL_DIR="$(cd "$(dirname "$_lib_src")/.." && pwd -P)"
SCRIPTS_DIR="$SKILL_DIR/scripts"
KINDS_FILE="$SKILL_DIR/references/kinds.json"

require_tools() {
  local t
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || die "'$t' not found on PATH"; done
}

require_herdr() {
  [ "${HERDR_ENV:-}" = "1" ] || die "not inside a Herdr pane (HERDR_ENV != 1); envoy-peer only runs under Herdr"
  require_tools herdr jq git
  [ -n "${HERDR_PANE_ID:-}" ] || die "HERDR_PANE_ID is unset"
}

kind_missing_msg() {
  echo "kind '$1' is not in $KINDS_FILE: run '$1 --help', confirm its full-permission flag, model flag and a secret-free auth probe, then add a row there."
}

# Print the kinds.json row of a kind; exit 1 when it has none.
kind_row() { jq -ce --arg k "$1" '.kinds[$k] // empty' "$KINDS_FILE"; }

kind_field() { jq -r --arg k "$1" --arg f "$2" '.kinds[$k][$f] // empty' "$KINDS_FILE"; }

kind_launch_args() { jq -r --arg k "$1" '.kinds[$k].launch_args[]' "$KINDS_FILE"; }

kind_verified() { jq -e --arg k "$1" '.kinds[$k].verified != null' "$KINDS_FILE" >/dev/null 2>&1; }

# Agent kinds this Herdr supports, one per line, parsed from the live help so
# the list is never hard-coded.
herdr_kinds() {
  local out
  out="$(herdr agent start --help 2>/dev/null \
    | sed -n '/--kind/,/possible values/s/.*\[possible values: \(.*\)\].*/\1/p' \
    | tr -d ',' | tr ' ' '\n' | sed '/^$/d')"
  [ -n "$out" ] || die "could not parse herdr kinds from 'herdr agent start --help'"
  printf '%s\n' "$out"
}

controller_kind() {
  herdr agent get "$HERDR_PANE_ID" 2>/dev/null | jq -r '.result.agent.agent // empty'
}

envoy_root() {
  local dir="${1:-$PWD}" top
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
  echo "${top:-$dir}/.envoy"
}

state_file() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/envoy-peer/state.json"; }

# Write stdin to a file atomically (temp file in the same folder, then mv), mode 600.
# Empty or invalid JSON (a failed jq upstream) leaves the old file untouched.
json_write_atomic() {
  local file="$1" tmp
  tmp="$(mktemp "$file.XXXXXX")"
  cat > "$tmp"
  if [ ! -s "$tmp" ] || ! jq empty "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo "$PROG: refusing to write empty or invalid JSON to $file" >&2
    return 1
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$file"
}

# with_lock <lockdir> <cmd...>: run cmd while holding a mkdir lock.
# Waits up to 5 s (50 x 100 ms); a lock older than 30 s is a crashed writer and is broken.
_LOCK_HELD=""
_lock_cleanup() { [ -z "$_LOCK_HELD" ] || rmdir "$_LOCK_HELD" 2>/dev/null || true; }
trap _lock_cleanup EXIT
with_lock() {
  local lock="$1" i=0 age rc=0; shift
  until mkdir "$lock" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
      age=$(( $(date +%s) - $(file_mtime "$lock" 2>/dev/null || date +%s) ))
      [ "$age" -gt 30 ] || die "lock busy: $lock"
      rmdir "$lock" 2>/dev/null || true
      i=0
      continue
    fi
    sleep 0.1
  done
  _LOCK_HELD="$lock"
  "$@" || rc=$?
  rmdir "$lock" 2>/dev/null || true
  _LOCK_HELD=""
  return "$rc"
}

# Modification time in epoch seconds (GNU stat first; BSD/macOS stat fallback).
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date -u +%s; }
iso_to_epoch() { jq -rn --arg t "$1" '$t | fromdateiso8601'; }

# kill_tree <pid>: signal pid and all its descendants, children first.
kill_tree() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done
  kill "$1" 2>/dev/null || true
}

# run_bounded <secs> <cmd...>: run cmd, kill its process tree after secs (macOS has no timeout(1)).
# The watchdog stops its own sleep when it is stopped, so nothing outlives the call.
run_bounded() {
  local secs="$1" pid w rc=0; shift
  "$@" &
  pid=$!
  ( sleep "$secs" & s=$!; trap 'kill "$s" 2>/dev/null; exit 0' TERM; wait "$s"; kill_tree "$pid" ) >/dev/null 2>&1 &
  w=$!
  wait "$pid" || rc=$?
  kill "$w" 2>/dev/null || true
  wait "$w" 2>/dev/null || true
  return "$rc"
}

# Mask secrets in terminal text before it reaches the user or a transcript.
redact() {
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{8,}/[redacted]/g' \
    -e 's/xai-[A-Za-z0-9_-]{8,}/[redacted]/g' \
    -e 's/eyJ[A-Za-z0-9_-]{10,}(\.[A-Za-z0-9_-]+)*/[redacted]/g' \
    -e 's/(code|token|key|secret|password|Code|Token|Key|Secret|Password|CODE|TOKEN|KEY|SECRET|PASSWORD)([=:][[:space:]]*)[^[:space:]]+/\1\2[redacted]/g' \
    -e 's/[A-Z0-9]{4}-[A-Z0-9]{4}/[redacted]/g' \
    -e 's/[A-Za-z0-9+=_-]{32,}/[redacted]/g'
}

# The `herdr pane list` row of a pane as compact JSON; empty when the pane is gone.
pane_row() {
  herdr pane list 2>/dev/null | jq -c --arg p "$1" '.result.panes[] | select(.pane_id == $p)'
}

# Status of the agent in a pane: idle|working|blocked|done|unknown, or the
# Herdr error code (agent_not_found, ...). Never prints pane content.
agent_state() {
  local out
  out="$(herdr agent get "$1" 2>&1 || true)"
  jq -r '.result.agent.agent_status // .error.code // "unknown"' <<<"$out" 2>/dev/null || echo unknown
}

# Matched state from the JSON of `herdr agent wait|prompt --wait` (stdout and stderr merged).
herdr_state() { jq -r '.result.agent.agent_status // .error.code // "unknown"' <<<"$1" 2>/dev/null || echo unknown; }

# ---- run.json ---------------------------------------------------------------

# resolve_run <dir>: absolute path of a run folder that holds run.json.
resolve_run() {
  [ -n "${1:-}" ] || usage_die "--run DIR is required"
  [ -f "$1/run.json" ] || die "no run.json in $1"
  (cd "$1" && pwd -P)
}

# run_get <dir> <jq path>: raw value, empty for null, objects/arrays as compact JSON.
run_get() {
  jq -r "$2"' | if . == null then empty elif type == "object" or type == "array" then tojson else . end' "$1/run.json"
}

# run_update <dir> <jq filter> [jq args...]: apply a filter to run.json under its
# lock and stamp updated_at. Filters may use $_now and nn ("" -> null).
_run_apply() {
  local f="$1" flt="$2" out; shift 2
  out="$(jq --arg _now "$(now_iso)" "$@" 'def nn: if . == "" then null else . end; ('"$flt"') | .updated_at = $_now' "$f")" || return 1
  printf '%s\n' "$out" | json_write_atomic "$f"
}
run_update() { local d="$1"; shift; with_lock "$d/run.json.lock" _run_apply "$d/run.json" "$@"; }

# ---- git snapshots ----------------------------------------------------------

git_top() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

sha_stdin() { shasum -a 256 | cut -d' ' -f1; }

# "sha  path" for every untracked, non-ignored file under a work tree.
untracked_manifest() (
  cd "$1" || exit 1
  git ls-files -o --exclude-standard -z | while IFS= read -r -d '' f; do
    shasum -a 256 -- "$f" 2>/dev/null || printf '%s  %s\n' - "$f"
  done
)

# "XY<TAB>sha<TAB>path" for every changed or untracked path (sha "-" when the path is gone).
worktree_manifest() (
  cd "$1" || exit 1
  git status --porcelain -uall --no-renames -z | while IFS= read -r -d '' e; do
    p="${e:3}"
    if [ -f "$p" ]; then s="$(shasum -a 256 < "$p" | cut -d' ' -f1)"; else s=-; fi
    printf '%s\t%s\t%s\n' "${e:0:2}" "$s" "$p"
  done
)

# One hash over .git/config and every non-sample hook (worktree-aware).
git_meta_sha() (
  cd "$1" || exit 1
  cfg="$(git rev-parse --git-path config)"
  hooks="$(git rev-parse --git-path hooks)"
  for f in "$cfg" "$hooks"/*; do
    case "$f" in *.sample) continue ;; esac
    [ -f "$f" ] || continue
    printf '%s ' "${f##*/}"
    shasum -a 256 < "$f"
  done | sha_stdin
)
