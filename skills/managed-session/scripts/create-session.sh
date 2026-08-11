#!/usr/bin/env bash
set -euo pipefail

CLI_CMD="claude"
CLI_LABEL="Claude Code"

if [ "${HERDR_ENV:-}" != "1" ]; then
  echo "Not running inside a Herdr-managed pane (HERDR_ENV=1 is unset)." >&2
  exit 1
fi

if ! command -v "$CLI_CMD" >/dev/null 2>&1; then
  echo "'$CLI_CMD' was not found on PATH." >&2
  exit 1
fi

p_name=""
s_name=""
split_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --p-name)
      [ "$#" -ge 2 ] || { echo "--p-name requires a value" >&2; exit 2; }
      p_name="$2"
      shift 2
      ;;
    --s-name)
      [ "$#" -ge 2 ] || { echo "--s-name requires a value" >&2; exit 2; }
      s_name="$2"
      shift 2
      ;;
    --split-r)
      [ -z "$split_dir" ] || { echo "--split-r and --split-d are mutually exclusive" >&2; exit 2; }
      split_dir="right"
      shift
      ;;
    --split-d)
      [ -z "$split_dir" ] || { echo "--split-r and --split-d are mutually exclusive" >&2; exit 2; }
      split_dir="down"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "${HERDR_WORKSPACE_ID:-}" ]; then
  echo "Missing HERDR_WORKSPACE_ID; is this really a Herdr-managed pane?" >&2
  exit 1
fi

if [ -n "$split_dir" ]; then
  split_json=$(herdr pane split --current --direction "$split_dir" --cwd "$PWD" --focus)
  target_pane=$(printf '%s' "$split_json" | jq -r '.result.pane.pane_id')
  target_tab="${HERDR_TAB_ID:-}"
else
  tab_json=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --focus)
  target_pane=$(printf '%s' "$tab_json" | jq -r '.result.root_pane.pane_id')
  target_tab=$(printf '%s' "$tab_json" | jq -r '.result.tab.tab_id')
fi

launch_cmd="$CLI_CMD"
if [ -n "$s_name" ]; then
  launch_cmd="$launch_cmd --name $(printf '%q' "$s_name")"
fi

herdr pane run "$target_pane" "$launch_cmd"

herdr agent wait "$target_pane" --status idle --timeout 30000 >/dev/null 2>&1 || true

if [ -n "$p_name" ]; then
  herdr pane rename "$target_pane" "$p_name" >/dev/null
fi

echo "Started $CLI_LABEL in pane $target_pane (tab $target_tab)."
