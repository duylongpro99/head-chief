#!/usr/bin/env bash
# Tests for supervisor-check.sh and `pending-watch.sh add --file` on a throwaway git
# repository, with stub `herdr` and `terminal-notifier` on PATH. No model, no real Herdr.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK="$HERE/../supervisor-check.sh"
PW="$HERE/../pending-watch.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/supervisor-check-test.XXXXXX")"
ROOT="$(cd "$ROOT" && pwd -P)"
export SUPERVISOR_HOME="$ROOT/supervisor" PENDING_POLL_SECONDS=1
export HERDR_STUB_PANES="$ROOT/panes"

mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/herdr" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pane list") cat "$HERDR_STUB_PANES" 2>/dev/null ;;
  "pane current") echo '{"result":{"pane":{"pane_id":"W:p1","tab_id":"W:t1"}}}' ;;
  "tab get") echo '{"result":{"tab":{"label":"sup","tab_id":"W:t1"}}}' ;;
esac
exit 0
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$ROOT/bin/terminal-notifier"
chmod +x "$ROOT/bin/herdr" "$ROOT/bin/terminal-notifier"
export PATH="$ROOT/bin:$PATH"

cleanup() { pkill -f "pending-watch.sh watch $ROOT" 2>/dev/null; rm -rf "$ROOT"; }
trap cleanup EXIT

pass=0; total=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
fail() { echo "FAIL - $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/       /'; }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
g() { git -C "$R" -c user.name=t -c user.email=t@example.com "$@"; }

# new_repo <name>: repository R on main with one commit, supervisor folder D inside it, setup run.
new_repo() {
  R="$ROOT/$1"; mkdir -p "$R/src" "$R/docs"
  git -C "$R" init -q -b main
  printf 'a = 1\nMAX_RETRIES = 30\nb = 2\n' > "$R/src/limits.py"
  printf '#!/bin/sh\necho "5/5 passed"\n' > "$R/test.sh"
  printf 'notes\n' > "$R/operator-notes.txt"   # untracked before supervision: the operator's
  g add src test.sh; g commit -q -m "chore: base"
  D="$R/plans/x-supervisor"; mkdir -p "$D"
  "$CHECK" setup "$D" --repo "$R" --main main --test 'sh test.sh' > /dev/null
}
# merge_branch <branch> <file> <content>: a --no-ff merge of one commit; sets SHA to the merge.
merge_branch() {
  g checkout -q -b "$1"; mkdir -p "$R/$(dirname "$2")"; printf '%s\n' "$3" > "$R/$2"
  g add "$2"; g commit -q -m "feat: $1"
  g checkout -q main; g merge -q --no-ff -m "merge $1" "$1"; g branch -q -D "$1"
  SHA="$(g rev-parse HEAD)"
}
run() { OUT="$("$@" 2>&1)"; RC=$?; }
# A passing accept is followed by confirm, as the supervisor does it.
run_ok() { run "$@"; if [ "$RC" -eq 0 ]; then "$CHECK" confirm "$D" "$4" > /dev/null 2>&1 || RC=9; fi; }

total=$((total + 1)); new_repo setup
if [ -f "$D/.check/conf" ] && grep -q 'operator-notes.txt' "$D/.check/status-baseline" \
  && [ "$(cat "$D/.check/verified-head")" = "$(g rev-parse main)" ]; then ok "setup writes conf, baseline and verified head"
else fail "setup writes conf, baseline and verified head"; fi

total=$((total + 1)); new_repo keep
before="$(cat "$D/.check/verified-head")"; echo x > "$R/later.txt"; g add later.txt; g commit -q -m "chore: later"
"$CHECK" setup "$D" --repo "$R" --main main > /dev/null
if [ "$(cat "$D/.check/verified-head")" = "$before" ] && grep -q '^test=sh test.sh$' "$D/.check/conf" \
  && ! grep -q later "$D/.check/status-baseline"; then ok "setup run again keeps the baseline, the verified head and the test command"
else fail "setup run again keeps the baseline, the verified head and the test command"; fi

total=$((total + 1)); new_repo pass; merge_branch m2 src/feature.py 'x = 1'
base="$(cat "$D/.check/verified-head")"
run "$CHECK" accept "$D" M2 "$SHA" --merge --scope src; out1="$OUT"
if [ "$RC" -eq 0 ] && has "RESULT: CHECKS PASS" && has "5/5 passed" && [ ! -f "$D/accepted.tsv" ] \
  && [ "$(cat "$D/.check/verified-head")" = "$base" ] && has "confirm"; then ok "accept passes a merge inside its scope but records nothing yet"
else fail "accept passes a merge inside its scope but records nothing yet" "$OUT"; fi

total=$((total + 1)); run "$CHECK" confirm "$D" M2; rc1=$RC; run "$CHECK" confirm "$D" M2
if [ "$rc1" -eq 0 ] && grep -q "^M2	" "$D/accepted.tsv" && [ "$(cat "$D/.check/verified-head")" = "$SHA" ] \
  && [ "$RC" -eq 1 ] && [ "$(grep -c . "$D/accepted.tsv")" -eq 1 ]; then ok "confirm records the item and moves the verified head, once"
else fail "confirm records the item and moves the verified head, once" "$OUT"; fi

total=$((total + 1)); new_repo moved; merge_branch m2 src/feature.py 'x = 1'
"$CHECK" accept "$D" M2 "$SHA" --merge --scope src > /dev/null 2>&1
echo n > "$R/src/n.py"; g add src; g commit -q -m "feat: later"
run "$CHECK" confirm "$D" M2; rc1=$RC; out1="$OUT"; run "$CHECK" confirm "$D" M9
if [ "$rc1" -eq 1 ] && printf '%s' "$out1" | grep -q "moved since accept" && [ ! -f "$D/accepted.tsv" ] && [ "$RC" -eq 1 ] && has "run accept first"; then ok "confirm refuses when main moved or accept never passed"
else fail "confirm refuses when main moved or accept never passed" "$out1$OUT"; fi

total=$((total + 1)); new_repo notmain; g checkout -q -b side; echo y > "$R/src/side.py"; g add src; g commit -q -m "feat: side"
SHA="$(g rev-parse HEAD)"; g checkout -q main
run "$CHECK" accept "$D" M2 "$SHA" --scope src
if [ "$RC" -eq 1 ] && has "is not on main" && [ ! -f "$D/accepted.tsv" ]; then ok "accept fails a commit that is not on main and records nothing"
else fail "accept fails a commit that is not on main and records nothing" "$OUT"; fi

total=$((total + 1)); new_repo notmerge; echo y > "$R/src/direct.py"; g add src; g commit -q -m "feat: direct"; SHA="$(g rev-parse HEAD)"
run "$CHECK" accept "$D" M2 "$SHA" --merge --scope src; rc1=$RC; out1="$OUT"
run_ok "$CHECK" accept "$D" M2 "$SHA" --scope src
if [ "$rc1" -eq 1 ] && printf '%s' "$out1" | grep -q "not a merge commit" && [ "$RC" -eq 0 ]; then ok "accept --merge fails a one-parent commit, which passes without --merge"
else fail "accept --merge fails a one-parent commit, which passes without --merge" "$out1$OUT"; fi

total=$((total + 1)); new_repo scope; merge_branch m2 docs/extra.md 'text'
run "$CHECK" accept "$D" M2 "$SHA" --merge --scope src
if [ "$RC" -eq 1 ] && has "outside the write scope: docs/extra.md"; then ok "accept fails a file outside the write scope"
else fail "accept fails a file outside the write scope" "$OUT"; fi

total=$((total + 1)); new_repo noscope; merge_branch m2 src/f.py 'x'
run "$CHECK" accept "$D" M2 "$SHA" --merge
if [ "$RC" -eq 1 ] && has "no --scope given"; then ok "accept fails when no write scope is given"
else fail "accept fails when no write scope is given" "$OUT"; fi

total=$((total + 1)); new_repo supdir; merge_branch m2 plans/x-supervisor/state.md 'edited by a worker'
run "$CHECK" accept "$D" M2 "$SHA" --merge --scope plans --scope src
if [ "$RC" -eq 1 ] && has "in the supervisor folder"; then ok "accept fails a commit that changes the supervisor folder"
else fail "accept fails a commit that changes the supervisor folder" "$OUT"; fi

total=$((total + 1)); new_repo unknown; echo z > "$R/src/stray.py"; g add src; g commit -q -m "feat: stray"; STRAY="$(g rev-parse HEAD)"
merge_branch m2 src/f.py 'x'
run "$CHECK" accept "$D" M2 "$SHA" --merge --scope src; rc1=$RC; out1="$OUT"
run_ok "$CHECK" accept "$D" M2 "$SHA" --merge --scope src --running "$STRAY"
if [ "$rc1" -eq 1 ] && printf '%s' "$out1" | grep -q "belongs to no named session" && [ "$RC" -eq 0 ] \
  && [ "$(cat "$D/.check/verified-head")" = "$(g rev-parse "$STRAY^")" ]; then ok "an unaccounted commit fails; --running passes and holds the verified head before it"
else fail "an unaccounted commit fails; --running passes and holds the verified head before it" "$out1$OUT"; fi

total=$((total + 1)); new_repo later; echo z > "$R/src/b.py"; g add src; g commit -q -m "feat: session b"; RB="$(g rev-parse HEAD)"
merge_branch m2 src/f.py 'x'; MA="$SHA"
run_ok "$CHECK" accept "$D" M2 "$MA" --merge --scope src/f.py --running "$RB"; rc1=$RC
run_ok "$CHECK" accept "$D" M3 "$RB" --scope src/b.py
if [ "$rc1" -eq 0 ] && [ "$RC" -eq 0 ] && [ "$(cat "$D/.check/verified-head")" = "$MA" ]; then ok "a session that reports after another one was accepted is not asked about the accepted commits"
else fail "a session that reports after another one was accepted is not asked about the accepted commits" "$OUT"; fi

total=$((total + 1)); new_repo rename; g checkout -q -b mv; mkdir -p "$R/config"; echo k > "$R/config/s.toml"; g add config; g commit -q -m "chore: add"; g checkout -q main; g merge -q mv; g branch -q -D mv
"$CHECK" setup "$D" --repo "$R" --main main > /dev/null; g rev-parse main > "$D/.check/verified-head"
g checkout -q -b m2; g mv config/s.toml src/s.toml; g commit -q -m "refactor: move"; g checkout -q main; g merge -q --no-ff -m "merge m2" m2; g branch -q -D m2
run "$CHECK" accept "$D" M2 "$(g rev-parse HEAD)" --merge --scope src
if [ "$RC" -eq 1 ] && has "outside the write scope: config/s.toml"; then ok "a rename out of a path outside the write scope fails"
else fail "a rename out of a path outside the write scope fails" "$OUT"; fi

total=$((total + 1)); new_repo also; merge_branch m2 src/f.py 'x'; M="$SHA"
echo done > "$R/docs/roadmap.md"; g add docs; g commit -q -m "docs: mark done"; DONE="$(g rev-parse HEAD)"
run "$CHECK" accept "$D" M2 "$M" --merge --scope src --also "$DONE"; rc1=$RC
run_ok "$CHECK" accept "$D" M2 "$M" --merge --scope src --scope docs/roadmap.md --also "$DONE"
if [ "$rc1" -eq 1 ] && [ "$RC" -eq 0 ]; then ok "--also commits are checked against the write scope too"
else fail "--also commits are checked against the write scope too" "$OUT"; fi

total=$((total + 1)); new_repo dirty; merge_branch m2 src/f.py 'x'
echo changed >> "$R/src/limits.py"; echo new > "$R/leftover.log"; echo s > "$D/state.md"
run "$CHECK" accept "$D" M2 "$SHA" --merge --scope src --no-tests; rc1=$RC; out1="$OUT"
run_ok "$CHECK" accept "$D" M2 "$SHA" --merge --scope src --no-tests --allow-dirty src/limits.py --allow-dirty '*.log'
if [ "$rc1" -eq 1 ] && printf '%s' "$out1" | grep -q "not clean: .*src/limits.py" && printf '%s' "$out1" | grep -q "leftover.log" \
  && ! printf '%s' "$out1" | grep -q "operator-notes\|x-supervisor\|plans" && [ "$RC" -eq 0 ]; then ok "a dirty main checkout fails; the baseline, the supervisor folder and --allow-dirty paths do not"
else fail "a dirty main checkout fails; the baseline, the supervisor folder and --allow-dirty paths do not" "$out1$OUT"; fi

total=$((total + 1)); new_repo tests; merge_branch m2 test.sh 'echo "4/5 passed"; exit 1'
run "$CHECK" accept "$D" M2 "$SHA" --merge --scope test.sh; rc1=$RC; out1="$OUT"
run_ok "$CHECK" accept "$D" M2 "$SHA" --merge --scope test.sh --no-tests
if [ "$rc1" -eq 1 ] && printf '%s' "$out1" | grep -q "test command exited 1" && printf '%s' "$out1" | grep -q "4/5 passed" \
  && [ "$RC" -eq 0 ] && grep -q "no-tests$" "$D/accepted.tsv"; then ok "a failing test command fails the report; --no-tests is recorded as such"
else fail "a failing test command fails the report; --no-tests is recorded as such" "$out1$OUT"; fi

total=$((total + 1)); new_repo evidence; merge_branch m2 src/f.py 'x'
printf 'no newline at end' >> "$R/src/f.py"; g add src; g commit -q -m "feat: tail"; TAIL="$(g rev-parse HEAD)"
printf 'Root cause: src/limits.py:2 sets MAX_RETRIES = 3. See also http://localhost:3000 and v1.2:3.\nAbsolute: %s/src/limits.py:3, worktree /tmp/wt/m2/src/limits.py:1, URL https://github.com/o/r/blob/main/src/f.py:2, bare notes.py:4.\n' "$R" > "$ROOT/report-ok.txt"
run "$CHECK" accept "$D" M2 "$SHA" --merge --also "$TAIL" --scope src --report "$ROOT/report-ok.txt"
if [ "$RC" -eq 0 ] && has "EVIDENCE" && has "src/limits.py:2> MAX_RETRIES = 30" && has "src/limits.py:3> b = 2" && has "src/limits.py:1> a = 1" \
  && has "src/f.py:2> no newline at end" && has "not checked: notes.py:4"; then ok "accept prints the cited line from main as evidence and ignores names that are not paths"
else fail "accept prints the cited line from main as evidence and ignores names that are not paths" "$OUT"; fi

total=$((total + 1)); new_repo badcite; merge_branch m2 src/f.py 'x'
printf 'Fixed in src/missing.py:4 and src/limits.py:99.\n' > "$ROOT/report-bad.txt"
run "$CHECK" accept "$D" M2 "$SHA" --merge --scope src --report "$ROOT/report-bad.txt"
if [ "$RC" -eq 1 ] && has "cited file does not exist on main: src/missing.py:4" && has "cited line does not exist on main: src/limits.py:99"; then ok "a cited file or line that does not exist fails the report"
else fail "a cited file or line that does not exist fails the report" "$OUT"; fi

total=$((total + 1)); new_repo resume
printf '# State\n## Config\nworker model: TBD\nloop: running\nloop: paused 2026-11-24 10:00\n## Decisions\n- loop: running again\n' > "$D/state.md"
printf '| m2-cook | W:p7 | ak:cook | opus | briefs/m2-cook.md | running | |\n| m1-review | W:p3 | ak:code-review | opus | b | stopped | abc |\n| m3-cook | W:p9 | ak:cook | opus | b | running | |\n| m4-stopped-after-running-out | W:p4 | ak:cook | opus | b | stopped | |\n' > "$D/sessions.md"
printf 'W:p7 m2-cook\nW:p91 other\n' > "$HERDR_STUB_PANES"
"$PW" init "$D" --session sup > /dev/null
printf 'M2\nCâu hỏi: 100%% of $HOME and `x`?\n- A: yes\nChặn: M2-cook\n' > "$ROOT/q.txt"
"$PW" add "$D" --file "$ROOT/q.txt" > /dev/null 2>&1
run "$CHECK" resume "$D"
if [ "$RC" -eq 0 ] && has "loop: paused" && has "has TBD value" && has "pane W:p7: open" && has "pane W:p9: NOT in herdr pane list" \
  && ! has "m1-review" && ! has "m4-stopped" && has "D1 · M2 · unseen" && has "watcher: OFF" && has "synced" && has "pending-watch.sh watch" \
  && has "The loop is paused" && has "Rules that were broken before:" && has "0 commit(s) not checked yet"; then ok "resume prints the state and what to do next"
else fail "resume prints the state and what to do next" "$OUT"; fi

total=$((total + 1))
printf '# State\n## Config\nloop: running\n## Items\n| M2 | commit: TBD |\n## Decisions\n- loop: paused while waiting on D1\n' > "$D/state.md"
: > "$HERDR_STUB_PANES"; run "$CHECK" resume "$D"
if has "loop: running" && ! has "The loop is paused" && ! has "TBD value" && has "pane list is unavailable" && ! has "NOT in herdr pane list"; then ok "resume reads loop and TBD from Config only, and does not call sessions gone when the pane list is empty"
else fail "resume reads loop and TBD from Config only, and does not call sessions gone when the pane list is empty" "$OUT"; fi

total=$((total + 1))
if grep -qF 'Câu hỏi: 100% of $HOME and `x`?' "$(cat "$D/ledger.path")"; then ok "add --file keeps %, \$ and backticks literal"
else fail "add --file keeps %, \$ and backticks literal" "$(cat "$(cat "$D/ledger.path")")"; fi

total=$((total + 1)); run "$PW" add "$D" --file "$ROOT/none.txt"
if [ "$RC" -ne 0 ] && has "usage: add"; then ok "add --file refuses a missing file"
else fail "add --file refuses a missing file" "$OUT"; fi

total=$((total + 1)); D2="$ROOT/bare"; mkdir -p "$D2"; run "$CHECK" resume "$D2"
if [ "$RC" -eq 0 ] && has "setup" && has "state.md: MISSING" && has "ledger: not live" && has "pending-watch.sh init"; then ok "resume on a folder without setup, state or ledger names each missing step"
else fail "resume on a folder without setup, state or ledger names each missing step" "$OUT"; fi

total=$((total + 1)); run "$CHECK" accept "$D2" M1 abc --scope src
if [ "$RC" -eq 2 ] && has "run:" ; then ok "accept without setup exits 2 and prints the setup command"
else fail "accept without setup exits 2 and prints the setup command" "$OUT"; fi

echo "$pass/$total passed"
[ "$pass" -eq "$total" ]
