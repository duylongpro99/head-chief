#!/usr/bin/env bash
set -euo pipefail

CLI_LABEL="Claude Code"

if [ "${HERDR_ENV:-}" != "1" ]; then
  echo "Not running inside a Herdr-managed pane (HERDR_ENV=1 is unset)." >&2
  exit 1
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: stop-session.sh <pane_id>" >&2
  exit 2
fi

pane_id="$1"

herdr pane run "$pane_id" "/exit" >/dev/null 2>&1 || true
sleep 1

if herdr pane close "$pane_id" >/dev/null 2>&1; then
  echo "Stopped $CLI_LABEL session and closed pane $pane_id."
else
  echo "Pane $pane_id was already gone; nothing to stop."
fi
