#!/usr/bin/env bash
# session.sh — Herdr lifecycle of the sessions in a pr-review-loop.
#
#   session.sh start   <session-name> [--model MODEL]    # spawn a fresh session, wait until idle, print pane id
#   session.sh restore <session-id> <cwd> [name]         # resume an offline session in a new tab, print pane id
#   session.sh compact <pane-id>                          # submit /compact and wait until idle again
#   session.sh self-compact [focus text]                  # queue /compact into THIS session's pane
#   session.sh status  <pane-id>                          # print agent_status (idle|working|...)
#   session.sh stop    <pane-id>                          # /exit + close pane
#
# Fresh sessions go through the managed-session skill's own script when it is
# installed (MANAGED_SESSION_DIR, then the usual skill folders); otherwise
# they are launched directly with herdr.
set -euo pipefail

find_ms() {
  local d
  for d in "${MANAGED_SESSION_DIR:-}" \
           "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills/managed-session" \
           "$HOME/.claude/skills/managed-session" \
           "$HOME/.agents/skills/managed-session"; do
    [ -n "$d" ] && [ -x "$d/scripts/create-session.sh" ] && { echo "$d"; return; }
  done
}
MS_DIR="$(find_ms || true)"

# Launch `claude <args>` in a new tab rooted at <cwd>; print the pane id.
launch_tab() {
  local dir="$1"; shift
  command -v jq >/dev/null || die "jq not on PATH"
  local pane
  pane=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$dir" \
    | jq -r '.result.root_pane.pane_id')
  [ -n "$pane" ] && [ "$pane" != null ] || die "could not create a tab"
  herdr pane run "$pane" "claude --dangerously-skip-permissions $(printf '%q ' "$@")"
  echo "$pane"
}

die() { echo "session.sh: $*" >&2; exit 1; }

[ "${HERDR_ENV:-}" = "1" ] || die "not inside Herdr (HERDR_ENV != 1); start the reviewer by hand"
command -v herdr >/dev/null || die "herdr not on PATH"

cmd="${1:-}"; shift || true

case "$cmd" in
  start)
    name="${1:-}"; [ -n "$name" ] || die "start needs a session name"; shift
    if [ -n "$MS_DIR" ]; then
      # --split-r keeps the new session visible next to this pane.
      out=$("$MS_DIR/scripts/create-session.sh" --s-name "$name" --p-name "$name" --split-r "$@")
      echo "$out" >&2
      pane=$(printf '%s\n' "$out" | sed -n 's/.*in pane \([^ ]*\) .*/\1/p' | head -1)
      [ -n "$pane" ] || die "could not parse pane id from create-session output"
    else
      pane=$(launch_tab "$PWD" --name "$name" "$@")
      herdr pane rename "$pane" "$name" >/dev/null 2>&1 || true
    fi
    # create-session's own wait uses a flag herdr no longer accepts, so wait here.
    herdr agent wait "$pane" --until idle --timeout 60000 >/dev/null 2>&1 \
      || echo "session.sh: pane $pane not idle after 60s (onboarding prompt?) — check it" >&2
    echo "$pane"
    ;;
  restore)
    sid="${1:-}"; dir="${2:-}"; name="${3:-}"
    [ -n "$sid" ] && [ -d "$dir" ] || die "restore needs a session id and its start cwd"
    # managed-session has no resume option. The cwd must be the session's
    # start cwd, or --resume cannot find it.
    if [ -n "$name" ]; then
      pane=$(launch_tab "$dir" --resume "$sid" --name "$name")
    else
      pane=$(launch_tab "$dir" --resume "$sid")
    fi
    herdr agent wait "$pane" --until idle --timeout 60000 >/dev/null 2>&1 \
      || echo "session.sh: pane $pane not idle after 60s — check it" >&2
    [ -n "$name" ] && herdr pane rename "$pane" "$name" >/dev/null 2>&1 || true
    echo "$pane"
    ;;
  compact)
    pane="${1:-}"; [ -n "$pane" ] || die "compact needs a pane id"
    herdr agent prompt "$pane" "/compact" --wait --until idle --timeout 600000 >/dev/null \
      || die "compact of $pane did not reach idle (still running or stalled)"
    echo "compacted $pane"
    ;;
  self-compact)
    pane="${HERDR_PANE_ID:-}"; [ -n "$pane" ] || die "HERDR_PANE_ID unset"
    # No --wait: this session is mid-turn, so the prompt is queued and runs
    # when the current turn ends.
    herdr agent prompt "$pane" "/compact ${*:-}" >/dev/null
    echo "queued /compact in $pane"
    ;;
  status)
    pane="${1:-}"; [ -n "$pane" ] || die "status needs a pane id"
    herdr agent get "$pane" | sed -n 's/.*"agent_status":"\([^"]*\)".*/\1/p'
    ;;
  stop)
    pane="${1:-}"; [ -n "$pane" ] || die "stop needs a pane id"
    if [ -n "$MS_DIR" ] && [ -x "$MS_DIR/scripts/stop-session.sh" ]; then
      "$MS_DIR/scripts/stop-session.sh" "$pane"
    else
      herdr pane run "$pane" "/exit" >/dev/null 2>&1 || true
      sleep 1
      herdr pane close "$pane" >/dev/null 2>&1 || true
      echo "stopped $pane"
    fi
    ;;
  *)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
