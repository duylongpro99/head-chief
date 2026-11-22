#!/usr/bin/env bash
# Tests for pending-watch.sh with stub `herdr` and `terminal-notifier` on PATH. No model, no real Herdr.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$HERE/../pending-watch.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pending-watch-test.XXXXXX")"
export PENDING_POLL_SECONDS=1 PENDING_RENOTIFY_SECONDS=3
export HERDR_STUB_LOG="$ROOT/herdr.log"
# Never touch the operator's real ~/supervisor.
export SUPERVISOR_HOME="$ROOT/supervisor"

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
# Stub terminal-notifier too, so a test run never raises a real desktop notification.
printf '#!/usr/bin/env bash\nprintf '"'"'terminal-notifier %%s\\n'"'"' "$*" >> "$HERDR_STUB_LOG"\n' > "$ROOT/bin/terminal-notifier"
chmod +x "$ROOT/bin/terminal-notifier"
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

# 11. The watcher exits when the Claude process that started it is gone.
total=$((total + 1)); new_case owner-gone
item 1 OPEN ' ' '' | sup_write
printf '#!/usr/bin/env bash\n"$@" &\nwait\n' > "$ROOT/bin/claude"; chmod +x "$ROOT/bin/claude"
"$ROOT/bin/claude" "$SCRIPT" watch "$D" > "$D/watch.out" 2>&1 &
owner=$!
wait_for 5 test -s "$D/.pending-state/owner"
WPID="$(cat "$D/.pending-state/pid" 2>/dev/null)"
recorded="$(cat "$D/.pending-state/owner" 2>/dev/null)"
wait_for 10 logged "tab rename W:t1 sup ⏳1"
kill -KILL "$owner" 2>/dev/null; wait "$owner" 2>/dev/null
if [ "$recorded" = "$owner" ] && wait_for 10 dead "$WPID" \
   && grep -qF "pending-watch: owner gone (pid $owner)" "$D/watch.out" \
   && [ ! -f "$D/.pending-state/pid" ] && [ "$(tail -n 1 "$HERDR_STUB_LOG")" = "tab rename W:t1 sup" ]; then
  ok "watcher exits and restores the label when its Claude owner dies"
else fail "watcher exits and restores the label when its Claude owner dies" "owner=$owner recorded=$recorded out=$(cat "$D/watch.out")"; kill "$WPID" 2>/dev/null; fi
WPID=""

# 12. Each notification also goes out as a clickable one that opens the ledger file.
total=$((total + 1)); new_case $'click m\xe1\xbb\x9f'; start_watch
printf '## D1 · M5 · OPEN · 2026-11-17 11:40\n[M5] judge model?\nSeen: [ ]\nAnswer:\n' | sup_write
real="$(cd "$D" && pwd -P)"
url="file://$(cd "$ROOT" && pwd -P)/click%20m%E1%BB%9F/pending-decisions.md"
if wait_for 10 logged "terminal-notifier -title ⏳ D1 mới -subtitle Bấm để mở pending-decisions.md -message \\[M5] judge model?" \
   && logged "📂 $real/pending-decisions.md -open $url -group pending-watch:$real:D1" \
   && logged "notification show ⏳ D1 mới --body [M5] judge model? --sound request"; then
  ok "clickable notification opens the ledger file"
else fail "clickable notification opens the ledger file" "url=$url log=$(cat "$HERDR_STUB_LOG")"; fi
stop_watch

# 13. Without terminal-notifier the Herdr notification is still sent.
total=$((total + 1)); new_case no-notifier
mv "$ROOT/bin/terminal-notifier" "$ROOT/terminal-notifier.off"
# A PATH of system folders only, so an installed terminal-notifier is not found either.
PATH="$ROOT/bin:/usr/bin:/bin" "$SCRIPT" watch "$D" > "$D/watch.out" 2>&1 &
WPID=$!
wait_for 5 test -f "$D/.pending-state/pid"
item 1 OPEN ' ' '' | sup_write
if ! PATH="$ROOT/bin:/usr/bin:/bin" command -v terminal-notifier > /dev/null \
   && wait_for 10 logged "notification show ⏳ D1 mới" && wait_for 5 logged "tab rename W:t1 sup ⏳1" \
   && kill -0 "$WPID" 2>/dev/null \
   && { [ "$(uname -s)" != Darwin ] || grep -qF "terminal-notifier not found" "$D/watch.out"; }; then
  ok "herdr notification is sent when terminal-notifier is missing"
else fail "herdr notification is sent when terminal-notifier is missing" "$(cat "$HERDR_STUB_LOG")"; fi
stop_watch
mv "$ROOT/terminal-notifier.off" "$ROOT/bin/terminal-notifier"

# 14. answers prints only the OPEN item that has an answer, whole, even with no blank line before the next item.
total=$((total + 1)); new_case answers
{ item 1 ANSWERED ' ' '2026-11-17 12:00 (chat) A'; item 2 OPEN ' ' ''; item 3 OPEN ' ' 'B, ghi số đo' | sed '$d'; item 4 OPEN ' ' ''; } | sup_write
expected="$(item 3 OPEN ' ' 'B, ghi số đo' | sed '$d')"
out="$("$SCRIPT" answers "$D")"
if [ "$out" = "$expected" ]; then ok "answers prints exactly the OPEN answered item"
else fail "answers prints exactly the OPEN answered item" "out=$out"; fi

# 15. A multi-line answer is printed whole, and two answered items are separated by one blank line.
total=$((total + 1)); new_case answers-multiline
first="$(item 1 OPEN ' ' 'line one' | sed '$d'; printf 'line two\n\nline four')"
{ printf '%s\n\n' "$first"; item 2 OPEN x 'C'; } | sup_write
expected="$(printf '%s\n\n' "$first"; item 2 OPEN x 'C' | sed '$d')"
out="$("$SCRIPT" answers "$D")"
if [ "$out" = "$expected" ]; then ok "answers prints a multi-line answer whole"
else fail "answers prints a multi-line answer whole" "out=$out"; fi

# 16. An empty ledger prints nothing and exits 0.
total=$((total + 1)); new_case answers-empty
out="$("$SCRIPT" answers "$D")"; rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ] && [ -z "$("$SCRIPT" list "$D")" ]; then ok "answers and list print nothing for an empty ledger"
else fail "answers and list print nothing for an empty ledger" "rc=$rc out=$out"; fi

# 17. A malformed header makes answers and list exit 2.
total=$((total + 1)); new_case answers-malformed
{ item 1 OPEN ' ' 'A'; printf '## D2 - M5 - OPEN\nbroken?\n'; } | sup_write
"$SCRIPT" answers "$D" > /dev/null 2>&1; rc=$?
"$SCRIPT" list "$D" > /dev/null 2>&1; rc2=$?
if [ "$rc" = 2 ] && [ "$rc2" = 2 ]; then ok "answers and list exit 2 on a malformed header"
else fail "answers and list exit 2 on a malformed header" "rc=$rc list=$rc2"; fi

# 18. list marks unseen, seen and answered items and skips ANSWERED ones.
total=$((total + 1)); new_case list
{ item 1 ANSWERED ' ' 'x'; item 2 OPEN ' ' ''; item 3 OPEN x ''; item 4 OPEN ' ' 'A'; } | sup_write
expected="D2 · M5 · unseen · Câu hỏi: question 2?
D3 · M5 · seen · Câu hỏi: question 3?
D4 · M5 · answered · Câu hỏi: question 4?"
out="$("$SCRIPT" list "$D")"
if [ "$out" = "$expected" ]; then ok "list marks unseen, seen and answered"
else fail "list marks unseen, seen and answered" "out=$out"; fi

# 19. record moves the item to the archive, stamps it ANSWERED, and a running watcher does not wake.
total=$((total + 1)); new_case record
{ item 1 OPEN ' ' ''; item 2 OPEN ' ' 'B'; item 3 OPEN ' ' ''; } | sup_write
start_watch
wait_for 10 logged "tab rename W:t1 sup ⏳2"
out="$("$SCRIPT" record "$D" D2 file 2>&1)"; rc=$?
A="$D/pending-decisions.archive.md"
if [ "$rc" = 0 ] && [ "$out" = D2 ] && ! grep -q '^## D2 ' "$D/pending-decisions.md" \
   && grep -q '^## D1 ' "$D/pending-decisions.md" && grep -q '^## D3 ' "$D/pending-decisions.md" \
   && [ "$(head -n 1 "$A")" = "# Answered decisions" ] \
   && grep -qE '^## D2 · M5 · ANSWERED · 2026-11-17 11:40$' "$A" \
   && grep -qE '^Answer: [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \(file\) B$' "$A" \
   && grep -qF -- '- A (đề xuất): flash' "$A" && grep -qF 'Chặn: M5-cook' "$A" \
   && sleep 3 && kill -0 "$WPID" 2>/dev/null; then
  ok "record archives the item, removes it from the ledger, and does not wake the watcher"
else fail "record archives the item, removes it from the ledger, and does not wake the watcher" "rc=$rc out=$out watch=$(cat "$D/watch.out") archive=$(cat "$A" 2>/dev/null)"; fi
stop_watch

# 20. Recording again after a crash between the archive write and the swap archives the item once.
total=$((total + 1)); new_case record-twice
item 1 OPEN ' ' '' | sup_write
"$SCRIPT" record "$D" D1 chat 'A' > /dev/null
item 1 OPEN ' ' '' | sup_write
out="$("$SCRIPT" record "$D" D1 chat 'A' 2>&1)"; rc=$?
second="$("$SCRIPT" record "$D" D1 chat 'A' 2>&1)"; rc2=$?
if [ "$rc" = 0 ] && [ "$(grep -c '^## D1 ' "$D/pending-decisions.archive.md")" = 1 ] \
   && ! grep -q '^## D1 ' "$D/pending-decisions.md" \
   && [ "$rc2" = 1 ] && printf '%s' "$second" | grep -qF "already recorded"; then
  ok "record twice archives the item once"
else fail "record twice archives the item once" "rc=$rc out=$out rc2=$rc2 second=$second"; fi

# 21. A ledger change between the read and the swap writes nothing and exits 3.
total=$((total + 1)); new_case record-race
item 1 OPEN ' ' 'A' | sup_write
before="$(shasum -a 256 < "$D/pending-decisions.md")"
out="$(PENDING_TEST_BEFORE_SWAP='printf "\n" >> "$LEDGER"' "$SCRIPT" record "$D" D1 file 2>&1)"; rc=$?
after_live="$(sed '$d' "$D/pending-decisions.md" | shasum -a 256)"
if [ "$rc" = 3 ] && [ "$out" = "pending-watch: ledger changed; run answers again" ] \
   && [ "$after_live" = "$before" ] && [ ! -e "$D/pending-decisions.archive.md" ] \
   && [ -z "$(ls -A "$D" | grep '^\.pending-\(snap\|new\)')" ]; then
  ok "a concurrent edit makes record exit 3 and write nothing"
else fail "a concurrent edit makes record exit 3 and write nothing" "rc=$rc out=$out files=$(ls -A "$D")"; fi

# 22. add numbers past items already archived.
total=$((total + 1)); new_case add
{ item 1 OPEN ' ' ''; item 2 OPEN ' ' ''; item 3 OPEN ' ' ''; } | sup_write
"$SCRIPT" record "$D" D3 dialog 'A (Recommended)' > /dev/null
id="$(printf 'M6\nCâu hỏi: giữ ngưỡng?\n- A (đề xuất): giữ\nChặn: p02-cook\n' | "$SCRIPT" add "$D" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ "$id" = D4 ] && "$SCRIPT" line "$D" > /dev/null \
   && grep -qE '^## D4 · M6 · OPEN · [0-9-]{10} [0-9:]{5}$' "$D/pending-decisions.md" \
   && [ "$("$SCRIPT" list "$D" | tail -n 1)" = "D4 · M6 · unseen · Câu hỏi: giữ ngưỡng?" ] \
   && [ "$(tail -n 2 "$D/pending-decisions.md" | tr '\n' '|')" = "Seen: [ ]|Answer:|" ]; then
  ok "add after an archived D3 returns D4"
else fail "add after an archived D3 returns D4" "rc=$rc id=$id ledger=$(cat "$D/pending-decisions.md")"; fi

# 23. A multi-line answer written in the file survives record, backslashes included.
total=$((total + 1)); new_case record-multiline
{ item 1 OPEN ' ' 'B, nhưng' | sed '$d'; printf '  ghi số đo C:\\new\n\nvào report\n\n'; item 2 OPEN ' ' ''; } | sup_write
"$SCRIPT" record "$D" D1 file > /dev/null
got="$(sed -n '/^Answer:/,$p' "$D/pending-decisions.archive.md")"
if printf '%s\n' "$got" | head -n 1 | grep -qE '^Answer: [0-9-]{10} [0-9:]{5} \(file\) B, nhưng$' \
   && [ "$(printf '%s\n' "$got" | tail -n +2)" = "$(printf '  ghi số đo C:\\new\n\nvào report')" ] \
   && grep -q '^## D2 ' "$D/pending-decisions.md"; then
  ok "record keeps a multi-line file answer"
else fail "record keeps a multi-line file answer" "got=$got"; fi

# 24. seen sets Seen: [x] and drops the item from line; a chat answer that contradicts the file is refused.
total=$((total + 1)); new_case seen-cmd
{ item 1 OPEN ' ' ''; item 2 OPEN ' ' ''; item 3 OPEN ' ' 'B'; } | sup_write
"$SCRIPT" seen "$D" D1 > /dev/null 2>&1; rc=$?
"$SCRIPT" record "$D" D3 chat 'A' > /dev/null 2>&1; rc2=$?
if [ "$rc" = 0 ] && [ "$("$SCRIPT" line "$D")" = "⏳ 1 đang chờ bạn (D2 mới) → $(cd "$D" && pwd -P)/pending-decisions.md (watcher off)" ] \
   && [ "$("$SCRIPT" list "$D" | head -n 1)" = "D1 · M5 · seen · Câu hỏi: question 1?" ] \
   && [ "$rc2" = 1 ] && grep -q '^## D3 · M5 · OPEN' "$D/pending-decisions.md" \
   && "$SCRIPT" seen "$D" D9 > /dev/null 2>&1; [ "$?" = 1 ]; then
  ok "seen marks the item; conflicting and unknown items are refused"
else fail "seen marks the item; conflicting and unknown items are refused" "rc=$rc rc2=$rc2 line=$("$SCRIPT" line "$D")"; fi

# Phase helpers for the shared folder: a git project with a supervisor folder inside it.
new_project() { # new_project <name>: sets P (project root) and D (supervisor folder, no ledger)
  P="$ROOT/projects/$1"; D="$P/plans/sup"
  mkdir -p "$D"; git -C "$P" init -q
  : > "$HERDR_STUB_LOG"
}
SH="$SUPERVISOR_HOME"

# 25. init writes the shared ledger with its header and ledger.path; watch and line use it.
total=$((total + 1)); new_project alpha
out="$("$SCRIPT" init "$D" --session alpha-sup 2>&1)"; rc=$?
F="$SH/alpha--alpha-sup.md"
RP="$(cd "$P" && pwd -P)"; RD="$(cd "$D" && pwd -P)"
if [ "$rc" = 0 ] && [ "$out" = "$F" ] && [ "$(cat "$D/ledger.path")" = "$F" ] \
   && [ "$(sed -n 1p "$F")" = "# Pending decisions" ] \
   && [ "$(sed -n 2p "$F")" = "Project: alpha · $RP" ] \
   && [ "$(sed -n 3p "$F")" = "Supervisor: alpha-sup · Herdr tab W:t1 · pane W:p1" ] \
   && sed -n 4p "$F" | grep -qE "^Started: [0-9-]{10} [0-9:]{5} · Archive: $RD/pending-decisions.archive.md$" \
   && [ ! -e "$D/pending-decisions.md" ]; then
  start_watch
  printf 'M1\nCâu hỏi: shared?\n' | "$SCRIPT" add "$D" > /dev/null
  if wait_for 10 logged "tab rename W:t1 sup ⏳1" && logged "-open file://$F" \
     && [ "$("$SCRIPT" line "$D")" = "⏳ 1 đang chờ bạn (D1) → $F" ] && grep -q '^## D1 · M1 · OPEN' "$F"; then
    ok "init creates the shared ledger and every command uses it"
  else fail "init creates the shared ledger and every command uses it" "log=$(cat "$HERDR_STUB_LOG")"; fi
  stop_watch
else fail "init creates the shared ledger and every command uses it" "rc=$rc out=$out file=$(cat "$F" 2>/dev/null)"; fi

# 26. init again for the same project reuses the file; another project with the same names is refused.
total=$((total + 1))
before="$(shasum -a 256 < "$F")"
out="$("$SCRIPT" init "$D" --session alpha-sup 2>&1)"; rc=$?
P1="$P"; new_project other; mkdir -p "$ROOT/projects/other2"; mv "$P" "$ROOT/projects/other2/alpha"
D="$ROOT/projects/other2/alpha/plans/sup"
out2="$("$SCRIPT" init "$D" --session alpha-sup 2>&1)"; rc2=$?
if [ "$rc" = 0 ] && [ "$(shasum -a 256 < "$F")" = "$before" ] && [ "$rc2" = 1 ] \
   && printf '%s' "$out2" | grep -qF "belongs to $RP" && [ ! -e "$D/ledger.path" ]; then
  ok "init reuses its own file and refuses another project's"
else fail "init reuses its own file and refuses another project's" "rc=$rc rc2=$rc2 out2=$out2"; fi

# 27. init migrates an old in-project ledger and stops its watcher.
total=$((total + 1)); new_project migrate
printf '# Pending decisions\n\n' > "$D/pending-decisions.md"
{ item 1 ANSWERED ' ' '2026-11-17 12:00 (chat) A'; item 2 OPEN ' ' ''; item 3 OPEN x ''; item 4 OPEN ' ' 'B'; } >> "$D/pending-decisions.md"
"$SCRIPT" synced "$D" > /dev/null
start_watch
oldpid="$WPID"
out="$("$SCRIPT" init "$D" --session mig-sup --tab T9 --pane P9 2>&1)"; rc=$?
wait "$oldpid" 2>/dev/null; WPID=""
F="$SH/migrate--mig-sup.md"
expected_open="$(item 2 OPEN ' ' ''; item 3 OPEN x ''; item 4 OPEN ' ' 'B' | sed '$d')"
A="$D/pending-decisions.archive.md"
if [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | tail -n 1)" = "$F" ] \
   && [ "$(tail -n +6 "$F")" = "$expected_open" ] && [ "$(sed -n 3p "$F")" = "Supervisor: mig-sup · Herdr tab T9 · pane P9" ] \
   && [ "$(grep -c '^## D' "$A")" = 1 ] && grep -q '^## D1 · M5 · ANSWERED' "$A" \
   && [ -f "$D/pending-decisions.md.migrated" ] && [ ! -e "$D/pending-decisions.md" ] \
   && dead "$oldpid" && printf '%s' "$out" | grep -qF "answered but not recorded yet: D4" \
   && [ "$("$SCRIPT" answers "$D")" = "$(item 4 OPEN ' ' 'B' | sed '$d')" ]; then
  ok "init migrates an old ledger: OPEN to the shared file, ANSWERED to the archive"
else fail "init migrates an old ledger: OPEN to the shared file, ANSWERED to the archive" "rc=$rc out=$out shared=$(cat "$F" 2>/dev/null)"; kill "$oldpid" 2>/dev/null; fi

# 28. A migration interrupted before the rename duplicates nothing when run again.
total=$((total + 1))
mv "$D/pending-decisions.md.migrated" "$D/pending-decisions.md"; rm -f "$D/ledger.path"
out="$("$SCRIPT" init "$D" --session mig-sup 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ "$(grep -c '^## D' "$A")" = 1 ] && [ "$(grep -c '^## D' "$F")" = 3 ] \
   && [ "$(tail -n +6 "$F")" = "$expected_open" ] && [ -f "$D/pending-decisions.md.migrated" ]; then
  ok "a repeated migration duplicates no item"
else fail "a repeated migration duplicates no item" "rc=$rc out=$out shared=$(cat "$F")"; fi

# 29. A migration that meets an operator save writes nothing and exits 3.
total=$((total + 1)); new_project migrate-race
printf '# Pending decisions\n\n' > "$D/pending-decisions.md"; item 1 OPEN ' ' '' >> "$D/pending-decisions.md"
out="$(PENDING_TEST_BEFORE_SWAP='printf "x\n" >> "$LEDGER"' "$SCRIPT" init "$D" --session r 2>&1)"; rc=$?
if [ "$rc" = 3 ] && [ -f "$D/pending-decisions.md" ] && [ ! -e "$SH/migrate-race--r.md" ] \
   && [ ! -e "$D/ledger.path" ] && [ -z "$(ls -A "$SH" | grep '^\.pending-')" ]; then
  ok "a migration that meets an operator save writes nothing"
else fail "a migration that meets an operator save writes nothing" "rc=$rc out=$out sh=$(ls -A "$SH")"; fi

# 30. close moves the ledger back into the project; list and record keep working on it.
total=$((total + 1)); new_project closing
"$SCRIPT" init "$D" --session c > /dev/null
F="$SH/closing--c.md"
printf 'M2\nCâu hỏi: still open?\n' | "$SCRIPT" add "$D" > /dev/null
printf 'M2\nCâu hỏi: answered?\n' | "$SCRIPT" add "$D" > /dev/null
"$SCRIPT" record "$D" D2 chat 'A' > /dev/null
start_watch
out="$("$SCRIPT" close "$D" 2>/dev/null)"; rc=$?
wait "$WPID" 2>/dev/null; WPID=""
FINAL="$(cd "$D" && pwd -P)/pending-decisions.final.md"
if [ "$rc" = 0 ] && [ "$out" = "$FINAL" ] && [ ! -e "$F" ] && [ -f "$FINAL" ] \
   && [ "$(cat "$D/ledger.path")" = "$FINAL" ] && [ ! -f "$D/.pending-state/pid" ] \
   && [ "$("$SCRIPT" list "$D")" = "D1 · M2 · unseen · Câu hỏi: still open?" ] \
   && grep -q '^## D2 · M2 · ANSWERED' "$D/pending-decisions.archive.md" \
   && [ "$("$SCRIPT" close "$D")" = "$FINAL" ]; then
  ok "close moves the ledger back and list still reads it"
else fail "close moves the ledger back and list still reads it" "rc=$rc out=$out sh=$(ls -A "$SH")"; fi

echo "$pass/$total passed"
[ "$pass" = "$total" ]
