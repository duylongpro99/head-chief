#!/usr/bin/env bash
set -euo pipefail

CLI_CMD="claude"
CLI_LABEL="Claude Code"

DEFAULT_COMPACT_WINDOW=400000

p_name=""
s_name=""
model=""
split_dir=""
skip_perms=1
backend="herdr"
compact_window="$DEFAULT_COMPACT_WINDOW"

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
    --model)
      [ "$#" -ge 2 ] || { echo "--model requires a value" >&2; exit 2; }
      model="$2"
      shift 2
      ;;
    --compact-window)
      [ "$#" -ge 2 ] || { echo "--compact-window requires a value" >&2; exit 2; }
      compact_window="$2"
      shift 2
      ;;
    --hc)
      backend="hc"
      shift
      ;;
    --no-skip-perms)
      skip_perms=0
      shift
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

if [ "$backend" = "hc" ]; then
  [ -z "$split_dir" ] || { echo "--split-r/--split-d are Herdr-only; hc terminals have no panes to split" >&2; exit 2; }
  command -v hc >/dev/null 2>&1 || { echo "'hc' (herdr core) was not found on PATH." >&2; exit 1; }
elif [ "${HERDR_ENV:-}" != "1" ]; then
  echo "Not running inside a Herdr-managed pane (HERDR_ENV=1 is unset). Use --hc to start it under herdr core instead." >&2
  exit 1
fi

if ! command -v "$CLI_CMD" >/dev/null 2>&1; then
  echo "'$CLI_CMD' was not found on PATH." >&2
  exit 1
fi

# Accept a token count as 400000, 400k or 1m; Claude Code's autoCompactWindow
# setting takes an integer between 100000 and 1000000.
normalize_tokens() {
  local lc
  lc="$(printf '%s' "$1" | tr -d '[:space:]_,' | tr '[:upper:]' '[:lower:]')"
  if [[ "$lc" =~ ^([0-9]+)k$ ]]; then
    printf '%s' "$((10#${BASH_REMATCH[1]} * 1000))"
  elif [[ "$lc" =~ ^([0-9]+)m$ ]]; then
    printf '%s' "$((10#${BASH_REMATCH[1]} * 1000000))"
  elif [[ "$lc" =~ ^[0-9]+$ ]]; then
    printf '%s' "$((10#$lc))"
  fi
}

compact_tokens="$(normalize_tokens "$compact_window")"
if [ -z "$compact_tokens" ] || [ "$compact_tokens" -lt 100000 ] || [ "$compact_tokens" -gt 1000000 ]; then
  echo "--compact-window must be a token count from 100k to 1m (e.g. 400000 or 400k), got: $compact_window" >&2
  exit 2
fi

# Accept human-friendly names like "sonnet 5.5", "Opus-5.5", "claude haiku 4.5"
# and turn them into model IDs (claude-sonnet-5-5). Aliases (sonnet, opus,
# opusplan, sonnet[1m]) and full/provider IDs are passed through untouched.
normalize_model() {
  local raw lc
  raw="$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  lc="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lc" =~ ^(claude[[:space:]_-]*)?(opus|sonnet|haiku|fable)[[:space:]_-]*([0-9]+)([.-]([0-9]+))?$ ]]; then
    local id="claude-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    [ -z "${BASH_REMATCH[5]}" ] || id="$id-${BASH_REMATCH[5]}"
    printf '%s' "$id"
  else
    printf '%s' "$raw"
  fi
}

if [ -n "$model" ]; then
  model="$(normalize_model "$model")"
  [ -n "$model" ] || { echo "--model requires a non-empty value" >&2; exit 2; }
fi

claude_args=()
if [ "$skip_perms" = 1 ]; then
  claude_args+=(--dangerously-skip-permissions)
fi
if [ -n "$model" ]; then
  claude_args+=(--model "$model")
fi
if [ -n "$s_name" ]; then
  claude_args+=(--name "$s_name")
fi
claude_args+=(--settings "{\"autoCompactWindow\":$compact_tokens}")

if [ "$backend" = "hc" ]; then
  hc_args=(run --bg --json --outlive-parent --cwd "$PWD" --label managed-session=claude)
  if [ -n "$p_name" ]; then
    hc_args+=(--name "$p_name")
  fi
  run_json=$(hc "${hc_args[@]}" "$CLI_CMD" "${claude_args[@]}")
  target_term=$(printf '%s' "$run_json" | jq -r '.address // empty')
  if [ -z "$target_term" ]; then
    echo "hc did not start the session: $run_json" >&2
    exit 1
  fi
  echo "Started $CLI_LABEL${model:+ (model $model)} in hc terminal $target_term${p_name:+ (name $p_name)}, auto-compact window $compact_tokens tokens. Attach with: hc attach $target_term"
  exit 0
fi

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
for arg in "${claude_args[@]}"; do
  launch_cmd="$launch_cmd $(printf '%q' "$arg")"
done

herdr pane run "$target_pane" "$launch_cmd"

# `herdr agent wait` fails at once with agent_not_found until Herdr has
# detected Claude Code in the pane, so poll the pane's own status instead.
ready=0
for _ in $(seq 1 60); do
  status=$(herdr pane get "$target_pane" 2>/dev/null | jq -r '.result.pane.agent_status // empty' || true)
  if [ "$status" = idle ]; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" != 1 ]; then
  echo "Warning: pane $target_pane is not idle after 60s (onboarding or trust prompt?); check it." >&2
fi

if [ -n "$p_name" ]; then
  herdr pane rename "$target_pane" "$p_name" >/dev/null
fi

echo "Started $CLI_LABEL${model:+ (model $model)} in pane $target_pane (tab $target_tab), auto-compact window $compact_tokens tokens."
