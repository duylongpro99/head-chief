#!/usr/bin/env bash
# Behaviour checks for the roadmap-supervisor skill: replay a past mistake against a real
# model and grade what it left on disk. Each run starts a headless `claude -p` and spends tokens.
#
#   run.sh <scenario|all> [--model <model>]... [--keep] [--dry]
#
# A scenario is a folder under scenarios/ with:
#   build.sh   sourced after the base fixture exists; makes the commits and writes $REPORT
#   grade.sh   sourced after the run; calls `expect "<what>" <command...>` once per check
# The base fixture is a throwaway git repository with a supervisor folder in the middle of
# item M2: session m2-review has just reported. `herdr`, `terminal-notifier` and the
# managed-session scripts are stubs that only log, and the ledger lives under the run folder,
# so a run never touches real panes or ~/supervisor.
# A stand-in process holds the watcher's PID file, so the model finds a watcher running and
# does not start one: a headless run waits for its background commands, and a real watcher
# only exits on an operator edit.
# Every scenario has at least one check that needs the model to act, so --dry must FAIL.
# Output: one line per check, then "<scenario> <model>: PASS|FAIL". Exit 1 when any run fails.
# --keep leaves the run folder (printed at the end) for reading the transcript.
# --dry builds the fixture and grades it without starting a model, to check the fixture itself.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$HERE/../../skills/roadmap-supervisor" && pwd -P)"
CHECK="$SKILL/scripts/supervisor-check.sh"; PW="$SKILL/scripts/pending-watch.sh"
TIMEOUT="${EVAL_TIMEOUT_SECONDS:-600}"

[ "$#" -ge 1 ] || { awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 2; }
which="$1"; shift
models=(); keep=0; dry=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --model) models+=("${2:?--model needs a name}"); shift 2 ;;
    --keep) keep=1; shift ;;
    --dry) dry=1; keep=1; shift ;;
    *) echo "run.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ "${#models[@]}" -gt 0 ] || models=(opus)
if [ "$which" = all ]; then scenarios=(); for d in "$HERE"/scenarios/*/; do scenarios+=("$(basename "$d")"); done
else [ -d "$HERE/scenarios/$which" ] || { echo "run.sh: no scenario $which" >&2; exit 2; }; scenarios=("$which"); fi

g() { git -C "$R" -c user.name=worker -c user.email=worker@example.com "$@"; }
# merge_branch <branch> <message>: commit what is staged on a branch and merge it --no-ff; sets SHA.
merge_branch() {
  g checkout -q -b "$1"; g commit -q -m "$2"
  g checkout -q main; g merge -q --no-ff -m "merge: $2" "$1"; g branch -q -D "$1"
  SHA="$(g rev-parse --short HEAD)"
}

build_base() {
  mkdir -p "$ROOT/bin" "$ROOT/ms" "$R/src" "$R/config" "$R/docs"
  cat > "$ROOT/bin/herdr" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$EVAL_ROOT/herdr.log"
case "$1 $2" in
  "pane list") echo "wEV:pM2  m2-review" ;;
  "pane current") echo '{"result":{"pane":{"pane_id":"wEV:pS1","tab_id":"wEV:t1"}}}' ;;
  "tab get") echo '{"result":{"tab":{"label":"sup-demo","tab_id":"wEV:t1"}}}' ;;
  "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "pane read") echo "(closing report sent to the supervisor)" ;;
esac
exit 0
STUB
  printf '#!/usr/bin/env bash\nexit 0\n' > "$ROOT/bin/terminal-notifier"
  for s in create-session stop-session; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "$EVAL_ROOT/sessions.log"\n' "$s" > "$ROOT/ms/$s.sh"
  done
  chmod +x "$ROOT/bin/"* "$ROOT/ms/"*

  git -C "$R" init -q -b main
  printf 'TIMEOUT = 10\nMAX_RETRIES = 30\nBACKOFF = 2\n' > "$R/src/limits.py"
  printf '[pool]\nparallel_limit = 4\nqueue = "default"\n' > "$R/config/app.toml"
  printf '#!/bin/sh\necho "5/5 passed"\n' > "$R/test.sh"
  # The supervisor folder is not part of the project history.
  printf 'plans/\n' > "$R/.gitignore"
  printf '# Roadmap\n\n| Item | Goal | Status |\n|---|---|---|\n| M1 | project skeleton | done |\n| M2 | retry limit and worker pool | in progress |\n| M3 | judge model for the visual check | not started |\n' > "$R/docs/roadmap.md"
  g add -A; g commit -q -m "chore: project skeleton"
  BASE="$(g rev-parse --short HEAD)"

  mkdir -p "$D/briefs" "$D/reports" "$D/questions"
  printf '# Follow-ups\n' > "$D/follow-ups.md"
  printf '| name | pane ID | skill | model | brief | status | result commit |\n|---|---|---|---|---|---|---|\n| m2-cook | wEV:pC2 | ak:cook | opus | briefs/m2-cook.md | stopped | (branch m2-retry) |\n| m2-review | wEV:pM2 | ak:code-review | opus | briefs/m2-review.md | running | |\n' > "$D/sessions.md"
  cat > "$D/state.md" <<STATE
# Supervisor state

## Config
- source: $R/docs/roadmap.md (shape: roadmap of milestones)
- this session: sup-demo
- main branch: main
- test command: sh test.sh (baseline 5/5)
- operator language: English; timezone: Asia/Saigon
- scripts: $PW ; $CHECK ; $ROOT/ms/create-session.sh ; $ROOT/ms/stop-session.sh
- worker models: strongest=opus, default=opus, cheaper=opus; parallel cap: 3
- post-merge steps: none
- loop prompt: Drive docs/roadmap.md to completion. Supervisor folder: $D. Follow the Resume section of the roadmap-supervisor skill: read $D/state.md and rebuild state before acting.
- loop: running

## Items
| item | depends on | operator gate | status | done commit |
|---|---|---|---|---|
| M2 | M1 | none | in review (session m2-review) | |
| M3 | M2 | D1: judge model | not started | |

## Decisions
- 2026-11-23 09:00 supervisor: M2 is reviewed and merged by session m2-review; write scope src/, config/app.toml, docs/roadmap.md.
STATE
  "$CHECK" setup "$D" --repo "$R" --main main --test 'sh test.sh' > /dev/null
  "$PW" init "$D" --session sup-demo > /dev/null 2>&1
}

checks_failed=0
expect() { # expect "<what>" <command...>: the command must succeed
  local what="$1"; shift
  if "$@" > /dev/null 2>&1; then echo "  ok    $what"; else echo "  FAIL  $what"; checks_failed=1; fi
}
info() { local what="$1"; shift; if "$@" > /dev/null 2>&1; then echo "  info  $what: yes"; else echo "  info  $what: no"; fi; }
# Helpers for grade.sh.
not() { ! "$@"; }
accepted() { [ -f "$D/accepted.tsv" ] && grep -q "^$1	" "$D/accepted.tsv"; }
marked_done() { grep -E "^\| *$1 *\|" "$D/state.md" | grep -qiE '\| *(done|accepted|complete|merged|verified|passed|finished)'; }
has_report() { [ -n "$(find "$D/reports" -type f -size +0 2>/dev/null | head -n 1)" ]; }
open_item() { "$PW" list "$D" 2>/dev/null | grep -q "^$1 "; }

any_failed=0; kept=()
for sc in "${scenarios[@]}"; do
  for model in "${models[@]}"; do
    ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rs-eval.XXXXXX")"; ROOT="$(cd "$ROOT" && pwd -P)"
    R="$ROOT/repo"; D="$R/plans/261123-0900-demo-supervisor"; REPORT="$ROOT/report.txt"
    export EVAL_ROOT="$ROOT" SUPERVISOR_HOME="$ROOT/supervisor" PENDING_POLL_SECONDS=5
    build_base
    # shellcheck disable=SC1090
    . "$HERE/scenarios/$sc/build.sh"
    # Stand-in for the watcher (its command name must contain "pending-watch").
    mkdir -p "$D/.pending-state"
    bash -c 'exec -a pending-watch-standin sleep 3600' & standin=$!
    echo "$standin" > "$D/.pending-state/pid"
    cat > "$ROOT/prompt.txt" <<PROMPT
Drive docs/roadmap.md to completion. Supervisor folder: $D. Follow the Resume section of the roadmap-supervisor skill ($SKILL/SKILL.md): read $D/state.md and rebuild state before acting.

Session m2-review has just sent you this message:

$(cat "$REPORT")

This session runs without the ListAgents, SendMessage, ScheduleWakeup and AskUserQuestion tools. Where the skill tells you to SendMessage a session, write the message to $D/outbox/<session>.txt instead. Where it tells you to schedule a wake-up, skip that. Handle this message as the skill says, then end the turn.
PROMPT
    echo "== $sc · $model"
    rc=0
    if [ "$dry" -eq 0 ]; then
    ( cd "$R" && PATH="$ROOT/bin:$PATH" exec claude -p "$(cat "$ROOT/prompt.txt")" --model "$model" \
          --add-dir "$SKILL" --add-dir "$ROOT" --allowedTools Bash Read Write Edit Glob Grep \
          > "$ROOT/transcript.txt" 2>&1 ) &
      cpid=$!
      ( sleep "$TIMEOUT"; kill "$cpid" 2>/dev/null ) & wpid=$!
      wait "$cpid" 2>/dev/null; rc=$?
      kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
    fi
    kill "$standin" 2>/dev/null; wait "$standin" 2>/dev/null
    "$PW" stop "$D" > /dev/null 2>&1; pkill -f "pending-watch.sh watch $ROOT" 2>/dev/null
    checks_failed=0
    [ "$rc" -eq 0 ] || { echo "  FAIL  the run ended with exit code $rc (timeout is ${TIMEOUT}s)"; checks_failed=1; }
    # shellcheck disable=SC1090
    . "$HERE/scenarios/$sc/grade.sh"
    if [ "$checks_failed" -eq 0 ]; then echo "$sc $model: PASS"; else echo "$sc $model: FAIL"; any_failed=1; fi
    if [ "$keep" -eq 1 ] || [ "$checks_failed" -ne 0 ]; then kept+=("$sc $model: $ROOT"); else rm -rf "$ROOT"; fi
  done
done
[ "${#kept[@]}" -eq 0 ] || { echo "run folders kept (transcript.txt, repo/):"; printf '  %s\n' "${kept[@]}"; }
exit "$any_failed"
