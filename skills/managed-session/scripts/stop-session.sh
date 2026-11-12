#!/usr/bin/env bash
set -euo pipefail

CLI_LABEL="Claude Code"

usage() {
  echo "Usage: stop-session.sh [--hc] <pane_id | hc_terminal>" >&2
  exit 2
}

backend="herdr"
if [ "${1:-}" = "--hc" ]; then
  backend="hc"
  shift
fi
[ "$#" -eq 1 ] || usage
target="$1"

if [ "$backend" = "hc" ]; then
  command -v hc >/dev/null 2>&1 || { echo "'hc' (herdr core) was not found on PATH." >&2; exit 1; }
  # Ask Claude Code to quit only if it is idle, so nothing lands in a busy prompt.
  hc send --if idle "$target" "/exit" >/dev/null 2>&1 || true
  sleep 1
  hc kill "$target" >/dev/null 2>&1 || true
  if hc rm "$target" >/dev/null 2>&1; then
    echo "Stopped $CLI_LABEL session and removed hc terminal $target."
  else
    echo "hc terminal $target was already gone; nothing to stop."
  fi
  exit 0
fi

if [ "${HERDR_ENV:-}" != "1" ]; then
  echo "Not running inside a Herdr-managed pane (HERDR_ENV=1 is unset). Use --hc for an hc terminal." >&2
  exit 1
fi

herdr pane run "$target" "/exit" >/dev/null 2>&1 || true
sleep 1

if herdr pane close "$target" >/dev/null 2>&1; then
  echo "Stopped $CLI_LABEL session and closed pane $target."
else
  echo "Pane $target was already gone; nothing to stop."
fi
