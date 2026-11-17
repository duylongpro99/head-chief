#!/usr/bin/env bash
# Tests for pending-watch.sh with a stub `herdr` on PATH. No model, no real Herdr.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$HERE/../pending-watch.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pending-watch-test.XXXXXX")"
export PENDING_POLL_SECONDS=1 PENDING_RENOTIFY_SECONDS=3
export HERDR_STUB_LOG="$ROOT/herdr.log"

mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/herdr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_STUB_LOG"
case "$1 $2" in
  "pane current") echo '{"id":"cli:pane:current","result":{"pane":{"pane_id":"W:p1","tab_id":"W:t1"},"type":"pane_current"}}' ;;
  "tab get") echo '{"id":"cli:tab:get","result":{"tab":{"label":"sup","tab_id":"W:t1"},"type":"tab_info"}}' ;;
esac
exit 0
EOF
chmod +x "$ROOT/bin/herdr"
export PATH="$ROOT/bin:$PATH"

WPID=""
cleanup() {
  [ -z "$WPID" ] || kill "$WPID" 2>/dev/null
  pkill -f "pending-watch.sh watch $ROOT" 2>/dev/null
  rm -rf "$ROOT"
}
trap cleanup EXIT

pass=0; total=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
fail() { echo "FAIL - $1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }

# wait_for <seconds> <command...>: retry until the command succeeds or time runs out.
wait_for() {
  local limit=$(( $1 * 5 )); shift
  local i
  for ((i = 0; i < limit; i++)); do "$@" && return 0; sleep 0.2; done
  return 1
}
logged() { grep -qF -- "$1" "$HERDR_STUB_LOG" 2>/dev/null; }
dead() { ! kill -0 "$1" 2>/dev/null; }

item() { # item <n> <status> <seen x|space> <answer>
  printf '## D%s · M5 · %s · 2026-11-17 11:40\nCâu hỏi: question %s?\n- A (đề xuất): flash\n- B: max\nChặn: M5-cook\nSeen: [%s]\nAnswer:%s\n\n' \
    "$1" "$2" "$1" "$3" "${4:+ $4}"
}

# new_case <name>: fresh folder with an empty ledger the supervisor has synced.
new_case() {
  D="$ROOT/$1"; mkdir -p "$D"
  printf '# Pending decisions\n\n' > "$D/pending-decisions.md"
  "$SCRIPT" synced "$D"
  : > "$HERDR_STUB_LOG"
}
start_watch() {
  "$SCRIPT" watch "$D" > "$D/watch.out" 2>&1 &
  WPID=$!
  wait_for 5 test -f "$D/.pending-state/pid"
}
stop_watch() { "$SCRIPT" stop "$D" > /dev/null 2>&1; wait "$WPID" 2>/dev/null; WPID=""; }
sup_write() { cat >> "$D/pending-decisions.md"; "$SCRIPT" synced "$D"; }

# 1. A new entry notifies and badges the tab.
total=$((total + 1)); new_case new-entry; start_watch
item 1 OPEN ' ' '' | sup_write
if wait_for 10 logged "notification show ⏳ D1 mới --body Câu hỏi: question 1? --sound request" \
   && wait_for 5 logged "tab rename W:t1 sup ⏳1"; then ok "new entry notifies and sets the tab to 'sup ⏳1'"
else fail "new entry notifies and badges the tab" "$(cat "$HERDR_STUB_LOG")"; fi
stop_watch

# 2. An operator edit of Answer: ends the watcher with user-edit.
total=$((total + 1)); new_case user-edit
item 1 OPEN ' ' '' | sup_write
start_watch
wait_for 10 logged "tab rename W:t1 sup ⏳1"
sed -i.bak 's/^Answer:$/Answer: A/' "$D/pending-decisions.md" && rm -f "$D/pending-decisions.md.bak"
if wait_for 10 dead "$WPID"; then
  wait "$WPID"; rc=$?; WPID=""
  if [ "$rc" = 0 ] && grep -qx "pending-watch: user-edit" "$D/watch.out"; then ok "operator edit exits 0 with user-edit"
  else fail "operator edit exits 0 with user-edit" "rc=$rc out=$(cat "$D/watch.out")"; fi
else fail "operator edit exits 0 with user-edit" "watcher still running"; stop_watch; fi

# 3. A supervisor write followed by synced does not end the watcher.
total=$((total + 1)); new_case synced-write; start_watch
item 1 OPEN ' ' '' | sup_write
item 2 OPEN ' ' '' | sup_write
if wait_for 10 logged "tab rename W:t1 sup ⏳2" && sleep 3 && kill -0 "$WPID" 2>/dev/null; then
  ok "supervisor write plus synced keeps the watcher running"
else fail "supervisor write plus synced keeps the watcher running" "$(cat "$D/watch.out")"; fi
stop_watch

# 4. Seen: [x] stops notifications and drops the item from the badge and the line.
total=$((total + 1)); new_case seen
{ item 1 OPEN x ''; item 2 OPEN ' ' ''; } | sup_write
start_watch
if wait_for 10 logged "tab rename W:t1 sup ⏳1" && sleep 4 \
   && ! logged "D1 mới" && ! logged "D1 vẫn chờ" && logged "D2 mới" \
   && line="$("$SCRIPT" line "$D")" && [ "$line" = "⏳ 1 đang chờ bạn (D2) → $(cd "$D" && pwd -P)/pending-decisions.md" ]; then
  ok "seen item is not notified, counted or listed"
else fail "seen item is not notified, counted or listed" "line='${line:-}' log=$(tr '\n' '|' < "$HERDR_STUB_LOG")"; fi
stop_watch

# 5. An open unseen item is notified again after the re-notify interval.
total=$((total + 1)); new_case renotify
item 1 OPEN ' ' '' | sup_write
start_watch
if wait_for 10 logged "⏳ D1 vẫn chờ"; then ok "open item is re-notified after the interval"
else fail "open item is re-notified after the interval" "$(cat "$HERDR_STUB_LOG")"; fi
stop_watch

# 6. A malformed header notifies an error and makes line exit non-zero.
total=$((total + 1)); new_case malformed
{ item 1 OPEN ' ' ''; printf '## D2 - M5 - OPEN\nCâu hỏi: broken?\nSeen: [ ]\nAnswer:\n'; } | sup_write
start_watch
"$SCRIPT" line "$D" > /dev/null 2> "$D/line.err"; rc=$?
if wait_for 10 logged "malformed header '## D2 - M5 - OPEN'" && [ "$rc" = 2 ] \
   && grep -qF "malformed header '## D2 - M5 - OPEN'" "$D/line.err"; then
  ok "malformed header notifies and line exits 2"
else fail "malformed header notifies and line exits 2" "rc=$rc log=$(cat "$HERDR_STUB_LOG")"; fi
stop_watch

# 7. stop restores the base label and leaves no watcher process.
total=$((total + 1)); new_case stop
item 1 OPEN ' ' '' | sup_write
start_watch
wait_for 10 logged "tab rename W:t1 sup ⏳1"
"$SCRIPT" stop "$D" > "$D/stop.out" 2>&1
wait_for 6 dead "$WPID"; wait "$WPID" 2>/dev/null; WPID=""
if [ "$(tail -n 1 "$HERDR_STUB_LOG")" = "tab rename W:t1 sup" ] \
   && ! pgrep -f "pending-watch.sh watch $ROOT" > /dev/null && [ ! -f "$D/.pending-state/pid" ] \
   && "$SCRIPT" line "$D" | grep -qF "(watcher off)"; then
  ok "stop restores the base label and leaves no process"
else fail "stop restores the base label and leaves no process" "log=$(tr '\n' '|' < "$HERDR_STUB_LOG") stop=$(cat "$D/stop.out")"; fi

# 8. synced lists an answer the operator saved that the supervisor has not recorded.
total=$((total + 1)); new_case synced-reports
item 1 OPEN ' ' 'B' >> "$D/pending-decisions.md"
out="$(item 2 OPEN ' ' '' | sup_write)"
if [ "$out" = "pending-watch: D1 has an answer in the file that is not recorded yet" ]; then
  ok "synced reports an unrecorded answer"
else fail "synced reports an unrecorded answer" "out='$out'"; fi

# 9. A stale pid that now belongs to another process is neither signalled nor blocking.
total=$((total + 1)); new_case stale-pid
item 1 OPEN ' ' '' | sup_write
sleep 300 & victim=$!
mkdir -p "$D/.pending-state"; echo "$victim" > "$D/.pending-state/pid"
"$SCRIPT" line "$D" > "$D/line.out"
"$SCRIPT" stop "$D" > /dev/null 2>&1
if kill -0 "$victim" 2>/dev/null && grep -qF "(watcher off)" "$D/line.out" \
   && start_watch && kill -0 "$WPID" 2>/dev/null; then
  ok "stale pid is not killed and does not block a new watcher"
else fail "stale pid is not killed and does not block a new watcher" "line=$(cat "$D/line.out")"; fi
kill "$victim" 2>/dev/null; wait "$victim" 2>/dev/null
stop_watch

# 10. CRLF line endings parse like LF.
total=$((total + 1)); new_case crlf
item 1 OPEN ' ' '' | sed 's/$/\r/' | sup_write
if line="$("$SCRIPT" line "$D" 2>&1)" && printf '%s' "$line" | grep -qF "⏳ 1 đang chờ bạn (D1 mới)"; then
  ok "CRLF ledger parses"
else fail "CRLF ledger parses" "line='$line'"; fi

echo "$pass/$total passed"
[ "$pass" = "$total" ]
