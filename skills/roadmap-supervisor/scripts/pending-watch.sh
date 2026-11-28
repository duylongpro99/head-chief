#!/usr/bin/env bash
# pending-watch.sh — keep a supervisor's pending-decisions ledger without calling any model.
#
#   pending-watch.sh init   <dir> --session <name> [--project <name>] [--tab <id>] [--pane <id>]
#   pending-watch.sh close  <dir>   # stop the watcher, move the ledger back into <dir>
#   pending-watch.sh watch  <dir> [--tab <tab-id>] [--base-label <label>]
#   pending-watch.sh synced <dir>   # accept the file as is: after a hand-written Conflict: line
#                                   # (same Bash call) and before restarting watch after a
#                                   # user-edit exit; lists answers in the file not recorded yet
#   pending-watch.sh answers <dir>  # full block of every OPEN item that has an answer
#   pending-watch.sh list   <dir>   # one line per OPEN item: D<n> · scope · unseen|seen|answered · question
#   pending-watch.sh line   <dir>   # one-line footer while items wait; nothing when none do
#   pending-watch.sh add    <dir> [--file <path>]  # item body from the file, or from stdin
#                                   # (scope line first); prints the new D<n>
#   pending-watch.sh record <dir> D<n> <dialog|chat|file> [text]  # stamp the answer, archive the item
#   pending-watch.sh seen   <dir> D<n>  # set Seen: [x]
#   pending-watch.sh stop   <dir>   # stop a running watcher and restore the tab label
#   pending-watch.sh action-add  <dir> --file <path>  # a step the operator must run; prints A<n>
#   pending-watch.sh action-done <dir> A<n> <text>    # the operator's confirmation, verbatim
#   pending-watch.sh action-list <dir>                # one line per OPEN action: A<n> · title
#
# watch: badges the Herdr tab "<base> ⏳N" (N = open, unseen items), notifies each new item
#   once and again every PENDING_RENOTIFY_SECONDS (default 1800), polls every
#   PENDING_POLL_SECONDS (default 5), and exits 0 with "pending-watch: user-edit" when the
#   ledger changes without a matching `synced` and stays unchanged for one more poll. After
#   that first line it prints the steps that must follow, with the real paths: answers,
#   record each answer, synced, then watch again in the background.
#   Run it with run_in_background so its exit wakes the supervisor.
#   --tab defaults to the tab of `herdr pane current`; --base-label overrides the label read
#   with `herdr tab get`.
#   Each notification is sent through Herdr and, when `terminal-notifier` is installed, also
#   as a desktop notification that opens the ledger file when clicked (a Herdr notification cannot
#   carry a click action).
#   When started under a Claude Code process, it exits with "pending-watch: owner gone" once
#   that process is gone, so a crashed or closed session leaves no watcher behind.
# line, answers, list: exit 2 on a malformed "## D" header. answers prints each block from
#   its "## D" line to the next "## " line, blocks separated by one blank line.
# add, record, seen: the only writers of the ledger. Each one builds the new file from a
#   snapshot and replaces the ledger only when it is still unchanged; otherwise it writes
#   nothing and exits 3. Each stores the new hash (like synced), names any other answer still
#   waiting in the file, and exits 1 for an unknown or non-OPEN D<n>.
#   add numbers the item after the highest D<n> in the ledger and the archive, so a number is
#   never reused. When no watcher is running for <dir>, add also warns on stderr and prints
#   the command that starts one; stdout stays the new D<n> and the exit code is unchanged.
#   record appends the answered item to <dir>/pending-decisions.archive.md (once
#   per D<n>) and then removes it from the ledger; for "file" the answer is the text already
#   in the item, for "dialog" and "chat" the text argument is required.
#
# add, action-add: refuse a body in which secret-scan.sh finds a likely secret (exit 1, the
#   hits named by line and kind, never the value).
# Actions: <dir>/operator-actions.md holds the steps the operator must run by hand, so they do
#   not scroll away in chat. action-add takes a file whose first line is the title, followed
#   by the steps or commands, a "Check:" line and a "Rollback:" line; it appends
#   "Reply: A<n> done"; it refuses a body line that starts with "## ". action-done marks the
#   action DONE with the time and the operator's words, which must be one line and hold no
#   likely secret. line lists OPEN actions before the decisions, and prints them even when no
#   decision waits.
#
# Ledger: the path in <dir>/ledger.path when that file exists, else <dir>/pending-decisions.md.
# init creates $SUPERVISOR_HOME/<project>--<session>.md (SUPERVISOR_HOME defaults to
#   ~/supervisor) with a header naming the project, the session, its Herdr tab and pane, the
#   folder, the start time and the archive, and writes ledger.path. It reuses that file when
#   it belongs to this project and this folder, and refuses one that belongs to another. When
#   <dir>/pending-decisions.md exists, or ledger.path names a final ledger left by close, init
#   stops the watcher and migrates that file: OPEN items go to the shared file, ANSWERED items
#   to the archive, and the old file gets a .migrated suffix. Answers still waiting are named,
#   for answers and record.
# close moves the ledger to <dir>/pending-decisions.final.md and points ledger.path at it.
# The archive and the state always stay in <dir>.
#
# State lives in <dir>/.pending-state/ (hash, pid, owner, tab, base-label, notified/<Dn>).
set -euo pipefail

die() { echo "pending-watch: $*" >&2; exit 1; }
# The usage text is the comment block at the top of this file, up to the first code line.
usage() { awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; }

notifier_warned=""
TEMPS=()
# The watcher installs its own EXIT trap; it creates no temp files.
cleanup_temps() { [ "${#TEMPS[@]}" -eq 0 ] || rm -f "${TEMPS[@]}"; }
POLL="${PENDING_POLL_SECONDS:-5}"
RENOTIFY="${PENDING_RENOTIFY_SECONDS:-1800}"

[ "$#" -ge 1 ] || { usage >&2; exit 2; }
cmd="$1"; shift
case "$cmd" in -h|--help|help) usage; exit 0 ;; esac
[ "$#" -ge 1 ] || die "$cmd needs the supervisor folder"
[ -d "$1" ] || die "no such folder: $1"
DIR="$(cd "$1" && pwd -P)"; shift
SUPERVISOR_HOME="${SUPERVISOR_HOME:-$HOME/supervisor}"
OLD_LEDGER="$DIR/pending-decisions.md"
if [ -s "$DIR/ledger.path" ]; then LEDGER="$(head -n 1 "$DIR/ledger.path")"; else LEDGER="$OLD_LEDGER"; fi
ARCHIVE="$DIR/pending-decisions.archive.md"
STATE="$DIR/.pending-state"
SELF="$(cd "$(dirname "$0")" && pwd -P)/${0##*/}"
SCAN="${SELF%/*}/secret-scan.sh"
ACTIONS="$DIR/operator-actions.md"

# run_line <subcommand>: the exact shell command that runs this script's <subcommand> on <dir>.
run_line() { printf '%q %s %q' "$SELF" "$1" "$DIR"; }

# An editor may rename the file away for a moment while saving; read that as "missing".
ledger_hash() {
  local h
  h="$( { shasum -a 256 < "$LEDGER"; } 2>/dev/null | awk '{print $1}')" || true
  echo "${h:-missing}"
}

# One record per item: id \t status \t seen(0|1) \t answered(0|1) \t question line \t scope.
# A bad "## D" header becomes: MALFORMED \t <line>.
parse() {
  [ -f "$LEDGER" ] || return 0
  LC_ALL=C awk -v SEP=" · " '
    { sub(/\r$/, "") }
    function flush() {
      if (id != "") printf "%s\t%s\t%d\t%d\t%s\t%s\n", id, status, seen, answered, question, scope
      id = ""
    }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    /^## / {
      flush()
      if ($0 !~ /^## D/) next
      n = split($0, p, SEP)
      if (n == 4 && p[1] ~ /^## D[0-9]+$/ && trim(p[2]) != "" && p[2] == trim(p[2]) \
          && p[3] ~ /^(OPEN|ANSWERED)$/ \
          && p[4] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]$/) {
        id = substr(p[1], 4); scope = p[2]; status = p[3]; seen = 0; answered = 0; question = ""; inanswer = 0
      } else {
        printf "MALFORMED\t%s\n", $0
      }
      next
    }
    id == "" { next }
    /^Seen:/ { inanswer = 0; if ($0 ~ /\[[xX]\]/) seen = 1; next }
    /^Answer:/ {
      inanswer = 1; rest = trim(substr($0, 8)); if (rest != "") answered = 1; next
    }
    inanswer { if (trim($0) != "") answered = 1; next }
    question == "" && trim($0) != "" { question = trim($0) }
    END { flush() }
  ' "$LEDGER" 2>/dev/null || true
}

# Filters parse output: counted items (open, unanswered, unseen) as "id \t question",
# or the malformed header lines.
select_counted() { awk -F'\t' '$1 != "MALFORMED" && $2 == "OPEN" && $3 == 0 && $4 == 0 { print $1 "\t" $5 }'; }
select_bad() { awk -F'\t' '$1 == "MALFORMED" { print $2 }'; }

# parse output, or exit 2 after naming each malformed header.
parse_checked() {
  local records bad
  records="$(parse)"
  bad="$(printf '%s\n' "$records" | select_bad)"
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" | while IFS= read -r l; do echo "pending-watch: malformed header '$l'" >&2; done
    exit 2
  fi
  printf '%s\n' "$records"
}

# blocks <ids...>: print the block of each named item, from its "## D" line up to the next
# "## " line, trailing blank lines dropped, blocks separated by one blank line.
blocks() {
  [ -f "$LEDGER" ] || return 0
  LC_ALL=C awk -v want=" $* " '
    { sub(/\r$/, "") }
    function flush() {
      while (n > 0 && buf[n] ~ /^[ \t]*$/) n--
      if (n > 0) { if (out++) print ""; for (i = 1; i <= n; i++) print buf[i] }
      n = 0; on = 0
    }
    /^## / {
      flush()
      if (match($0, /^## D[0-9]+ /) && index(want, " " substr($0, 4, RLENGTH - 4) " ")) on = 1
    }
    on { buf[++n] = $0 }
    END { flush() }
  ' "$LEDGER"
}

# A recorded pid counts only while it is a pending-watch process: after a crash or a
# reboot the number may belong to something else, which must never be signalled.
pid_alive() {
  local pid
  [ -f "$STATE/pid" ] || return 1
  pid="$(cat "$STATE/pid")"
  kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q 'pending-watch'
}

restore_label() {
  if [ -f "$STATE/tab" ] && [ -f "$STATE/base-label" ]; then
    herdr tab rename "$(cat "$STATE/tab")" "$(cat "$STATE/base-label")" >/dev/null 2>&1 || true
  fi
}

# True when one of the first two words of the process's command is named "claude"
# ("claude --flags", or "bash /path/claude" for a script).
is_claude() {
  ps -o command= -p "$1" 2>/dev/null \
    | awk '{ for (i = 1; i <= 2 && i <= NF; i++) { n = $i; sub(/.*\//, "", n); if (n == "claude") f = 1 } } END { exit !f }'
}

# Nearest Claude Code ancestor of this watcher, or nothing when started by hand.
find_owner() {
  local p="$PPID"
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    if is_claude "$p"; then echo "$p"; return 0; fi
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  done
}

json_field() { sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p" | head -n 1; }

# file_url <path>: file:// URL, percent-encoded byte by byte so spaces and non-ASCII names survive.
file_url() {
  local LC_ALL=C s="$1" out="" c i n
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9/._~-]) out="$out$c" ;;
      # Old bash reports a byte above 127 as a negative number; keep the low 8 bits.
      *) n="$(printf '%d' "'$c")"; out="$out$(printf '%%%02X' $((n & 255)))" ;;
    esac
  done
  printf 'file://%s' "$out"
}

# notify <group> <title> <body>: the Herdr notification, plus a clickable one that opens
# the ledger file. <group> makes a reminder replace the earlier notification of the
# same item instead of stacking.
notify() {
  local group="$1" title="$2" body="$3"
  herdr notification show "$title" --body "$body" --sound request >/dev/null 2>&1 || true
  command -v terminal-notifier >/dev/null 2>&1 || return 0
  # terminal-notifier reads a leading "[", "(", "<" or "-" as syntax unless it is escaped.
  case "$body" in '['*|'('*|'<'*|-*) body="\\$body" ;; esac
  # macOS shows the title and the subtitle on one line each and wraps only the message, so
  # the subtitle carries just the file name and the full path goes on its own message line.
  local err short="$LEDGER"
  case "$LEDGER" in "$HOME"/*) short="~${LEDGER#"$HOME"}" ;; esac
  body="$body
📂 $short"
  if ! err="$(terminal-notifier -title "$title" -subtitle "Bấm để mở ${LEDGER##*/}" -message "$body" \
      -open "$(file_url "$LEDGER")" -group "pending-watch:$DIR:$group" 2>&1 >/dev/null </dev/null)"; then
    # Usually macOS has notifications switched off for terminal-notifier. Say so once.
    [ -n "$notifier_warned" ] || echo "pending-watch: terminal-notifier failed, no clickable notification: $err" >&2
    notifier_warned=1
  fi
}

# new_temp: a fresh file next to the ledger (so mv onto it is atomic), removed on exit unless moved.
new_temp() {
  local f
  f="$(mktemp "$(dirname "$LEDGER")/.pending-new.XXXXXX")"
  TEMPS+=("$f")
  trap cleanup_temps EXIT
  printf '%s' "$f"
}

# Highest D<n> number in the ledger, the archive, final ledgers left by close and an old
# in-project ledger, 0 when there is none. A restarted supervisor never reuses a number.
max_id() {
  local f files=()
  for f in "$LEDGER" "$ARCHIVE" "$OLD_LEDGER" "$DIR"/pending-decisions.final*.md; do [ ! -f "$f" ] || files+=("$f"); done
  [ "${#files[@]}" -gt 0 ] || { echo 0; return 0; }
  LC_ALL=C awk '/^## D[0-9]+ / { n = substr($2, 2) + 0; if (n > m) m = n } END { print m + 0 }' "${files[@]}"
}

now_stamp() { date '+%Y-%m-%d %H:%M'; }

# Prints the parse record of one item, or nothing.
record_of() { parse | awk -F'\t' -v id="$1" '$1 == id'; }

# Snapshot the ledger so the new content is built from one consistent read. Sets SNAP and SNAP_HASH.
take_snapshot() {
  [ -f "$LEDGER" ] || die "no ledger at $LEDGER"
  SNAP="$(mktemp "$(dirname "$LEDGER")/.pending-snap.XXXXXX")"
  TEMPS+=("$SNAP")
  trap cleanup_temps EXIT
  cp "$LEDGER" "$SNAP"
  SNAP_HASH="$(shasum -a 256 < "$SNAP" | awk '{print $1}')"
}

# swap_ledger <new-file>: replace the ledger with <new-file> only when the ledger still matches
# the snapshot. The new file lives in the ledger's folder, so mv is atomic.
# ensure_unchanged: exit 3, having written nothing, when the ledger no longer matches the snapshot.
ensure_unchanged() {
  if [ -n "${PENDING_TEST_BEFORE_SWAP:-}" ]; then eval "$PENDING_TEST_BEFORE_SWAP"; PENDING_TEST_BEFORE_SWAP=""; fi
  if [ "$(ledger_hash)" != "$SNAP_HASH" ]; then
    echo "pending-watch: ledger changed; run answers again" >&2
    exit 3
  fi
}

swap_ledger() {
  local new="$1"
  ensure_unchanged
  mkdir -p "$STATE"
  mv "$new" "$LEDGER"
  ledger_hash > "$STATE/hash"
}

# Name answers still waiting in the file, other than <except>; storing the new hash means the
# watcher will not report them.
report_waiting() {
  parse | awk -F'\t' -v skip="${1:-}" '$1 != "MALFORMED" && $2 == "OPEN" && $4 == 1 && $1 != skip { print $1 }' \
    | while IFS= read -r id; do
        echo "pending-watch: $id has an answer in the file that is not recorded yet" >&2
      done
}

# require_open <D<n>>: exit 1 unless the ledger holds that item as OPEN.
require_open() {
  local rec
  case "$1" in D[0-9]*) ;; *) die "not an item id: $1 (expected D<n>)" ;; esac
  parse_checked > /dev/null || exit $?
  rec="$(record_of "$1")"
  if [ -z "$rec" ]; then
    if grep -q "^## $1 · " "$ARCHIVE" 2>/dev/null; then die "$1 is already recorded in $ARCHIVE"; fi
    die "no item $1 in $LEDGER"
  fi
  [ "$(printf '%s' "$rec" | cut -f2)" = OPEN ] || die "$1 is not OPEN"
}

# refuse_secrets <file> <what>: exit 1, naming each hit without its value, when the file looks
# like it holds a secret.
refuse_secrets() {
  local hits
  hits="$("$SCAN" "$1" 2>&1)" && return 0
  printf '%s\n' "$hits" | sed "s|^$1:|line |" | while IFS= read -r l; do echo "pending-watch: $2 looks like it holds a secret: $l" >&2; done
  die "$2 refused: name the Keychain item or environment variable instead of its value"
}

# One record per action in operator-actions.md: id \t status \t title.
action_records() {
  [ -f "$ACTIONS" ] || return 0
  LC_ALL=C awk -F' · ' '{ sub(/\r$/, "") } /^## A[0-9]+ · (OPEN|DONE) · / { t = $0; sub(/^([^·]*· ){3}/, "", t); print substr($1, 4) "\t" $2 "\t" t }' "$ACTIONS"
}

cmd_action_add() {
  [ "$#" -eq 2 ] && [ "$1" = --file ] && [ -f "$2" ] || die "usage: action-add <dir> --file <path>"
  local body title rest n id new
  body="$(LC_ALL=C sed 's/\r$//' "$2")"
  title="$(printf '%s\n' "$body" | head -n 1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  rest="$(printf '%s\n' "$body" | tail -n +2)"
  [ -n "$title" ] || die "action-add: the first line must be the title"
  case "$title" in *" · "*|"#"*) die "action-add: the title must not contain ' · ' or start with '#'" ;; esac
  printf '%s\n' "$rest" | grep -q '^Check:' || die "action-add: add a 'Check:' line: how the operator sees that it worked"
  printf '%s\n' "$rest" | grep -q '^Rollback:' || die "action-add: add a 'Rollback:' line: how to undo it, or 'none needed' and why"
  [ -n "$(printf '%s\n' "$rest" | grep -v -e '^Check:' -e '^Rollback:' | tr -d '[:space:]')" ] || die "action-add: no steps or commands between the title and Check:"
  # A "## " line would read as the start of another action and split this one.
  ! printf '%s\n' "$rest" | grep -q '^## ' || die "action-add: no line may start with '## '; use '### ' or a numbered list for steps"
  refuse_secrets "$2" "action-add"
  n="$(action_records | awk -F'\t' '{ v = substr($1, 2) + 0; if (v > m) m = v } END { print m + 0 }')"
  id="A$((n + 1))"
  new="$(mktemp "$DIR/.actions-new.XXXXXX")"; TEMPS+=("$new"); trap cleanup_temps EXIT
  {
    if [ -f "$ACTIONS" ]; then trim_trailing_blank < "$ACTIONS"
    else printf '# Operator actions\nSteps only the operator can run. Reply in chat with the Reply: line of each one.\n'; fi
    echo
    printf '## %s · OPEN · %s · %s\n' "$id" "$(now_stamp)" "$title"
    printf '%s\n' "$rest" | trim_trailing_blank | LC_ALL=C awk 'NF { s = 1 } s'
    printf 'Reply: %s done (or say what failed)\n' "$id"
  } > "$new"
  mv "$new" "$ACTIONS"
  echo "$id"
}

cmd_action_done() {
  [ "$#" -eq 2 ] && [ -n "$(printf '%s' "$2" | tr -d '[:space:]')" ] || die "usage: action-done <dir> A<n> '<the operator's words>'"
  local id="$1" st new
  case "$id" in A[0-9]*) ;; *) die "not an action id: $id (expected A<n>)" ;; esac
  # One line only: a second line could start a fake "## A<n>" header.
  case "$2" in *$'\n'*|*$'\r'*) die "action-done: the operator's words must be one line; join the lines with ' / '" ;; esac
  local said
  said="$(mktemp "${TMPDIR:-/tmp}/pending-done.XXXXXX")"; TEMPS+=("$said"); trap cleanup_temps EXIT
  printf '%s\n' "$2" > "$said"
  refuse_secrets "$said" "action-done"
  st="$(action_records | awk -F'\t' -v id="$id" '$1 == id { print $2 }')"
  [ -n "$st" ] || die "no action $id in $ACTIONS"
  [ "$st" = OPEN ] || die "$id is already $st"
  new="$(mktemp "$DIR/.actions-new.XXXXXX")"; TEMPS+=("$new"); trap cleanup_temps EXIT
  # The answer goes through the environment: awk -v would expand backslashes in it.
  STAMP="$(now_stamp)" ANS="$2" LC_ALL=C awk -v id="$id" '
    { sub(/\r$/, "") }
    function flush(last) {
      if (on) {
        while (n > 0 && buf[n] ~ /^[ \t]*$/) n--
        for (i = 1; i <= n; i++) print buf[i]
        print "Done: " ENVIRON["STAMP"] " " ENVIRON["ANS"]
        if (!last) print ""
      }
      n = 0; on = 0
    }
    /^## / { flush(0); if (index($0, "## " id " · OPEN · ") == 1) { sub(/ · OPEN · /, " · DONE · "); on = 1 } }
    on { buf[++n] = $0; next }
    { print }
    END { flush(1) }' "$ACTIONS" > "$new"
  mv "$new" "$ACTIONS"
  echo "$id"
}

cmd_action_list() { action_records | awk -F'\t' '$2 == "OPEN" { print $1 " · " $3 }'; }

cmd_add() {
  local body scope rest id new
  if [ "${1:-}" = --file ]; then
    [ "$#" -eq 2 ] && [ -f "$2" ] || die "usage: add <dir> --file <path>"
    body="$(cat "$2")"
  else
    [ "$#" -eq 0 ] || die "usage: add <dir> [--file <path>]"
    body="$(cat)"
  fi
  local scanned
  scanned="$(mktemp "${TMPDIR:-/tmp}/pending-add.XXXXXX")"; TEMPS+=("$scanned"); trap cleanup_temps EXIT
  printf '%s\n' "$body" > "$scanned"
  refuse_secrets "$scanned" "add"
  scope="$(printf '%s\n' "$body" | head -n 1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  rest="$(printf '%s\n' "$body" | tail -n +2)"
  [ -n "$scope" ] || die "add: the first stdin line must be the scope"
  case "$scope" in *" · "*) die "add: the scope must not contain ' · '" ;; esac
  [ -n "$(printf '%s' "$rest" | tr -d '[:space:]')" ] || die "add: no question after the scope line"
  parse_checked > /dev/null || exit $?
  take_snapshot
  id="D$(( $(max_id) + 1 ))"
  new_temp > /dev/null; new="${TEMPS[${#TEMPS[@]}-1]}"
  {
    # Drop trailing blank lines, then end with exactly one blank line before the new item.
    LC_ALL=C awk '{ sub(/\r$/, ""); l[NR] = $0 } END { n = NR; while (n > 0 && l[n] ~ /^[ \t]*$/) n--; for (i = 1; i <= n; i++) print l[i]; if (n) print "" }' "$SNAP"
    printf '## %s · %s · OPEN · %s\n' "$id" "$scope" "$(now_stamp)"
    printf '%s\n' "$rest" | LC_ALL=C awk '{ l[NR] = $0 } END { n = NR; while (n > 0 && l[n] ~ /^[ \t]*$/) n--; s = 1; while (s <= n && l[s] ~ /^[ \t]*$/) s++; for (i = s; i <= n; i++) print l[i] }'
    printf 'Seen: [ ]\nAnswer:\n'
  } > "$new"
  swap_ledger "$new"
  echo "$id"
  report_waiting
  # Without a watcher the item gets no tab badge or notification, and an answer saved in the
  # file wakes nobody.
  pid_alive || echo "pending-watch: no watcher is running, so $id gets no badge or notification and a file answer will not wake you; start it with run_in_background: $(run_line watch)" >&2
}

# rewrite_item <D<n>> <awk program>: run the program over the snapshot with id set, into a
# new file next to the ledger, whose path it leaves in REWRITTEN. The program sees "in_item" true on
# the lines of that item's block.
rewrite_item() {
  new_temp > /dev/null; REWRITTEN="${TEMPS[${#TEMPS[@]}-1]}"
  LC_ALL=C awk -v id="$1" '
    { sub(/\r$/, "") }
    /^## / { in_item = ($0 ~ ("^## " id " · ")) }
    '"$2" "$SNAP" > "$REWRITTEN"
}

cmd_seen() {
  [ "$#" -eq 1 ] || die "usage: seen <dir> D<n>"
  local id="$1"
  require_open "$id"
  take_snapshot
  rewrite_item "$id" '
    in_item && /^Seen:/ { print "Seen: [x]"; done = 1; next }
    in_item && /^Answer:/ && !done { print "Seen: [x]"; done = 1 }
    { print }'
  swap_ledger "$REWRITTEN"
  echo "$id"
  report_waiting
}

cmd_record() {
  [ "$#" -ge 2 ] || die "usage: record <dir> D<n> <dialog|chat|file> [text]"
  local id="$1" channel="$2" text="${3:-}" block filed item
  case "$channel" in
    file) [ "$#" -eq 2 ] || die "record ... file takes no text: the answer is the one in the file" ;;
    dialog|chat) [ "$#" -eq 3 ] && [ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] \
        || die "record ... $channel needs the operator's answer as the text argument" ;;
    *) die "unknown channel: $channel (dialog, chat or file)" ;;
  esac
  require_open "$id"
  take_snapshot
  block="$(LEDGER="$SNAP" blocks "$id")"
  # The answer already written in the item: text after "Answer:" and every line below it.
  filed="$(printf '%s\n' "$block" | LC_ALL=C awk '
    on { print; next }
    /^Answer:/ { on = 1; r = substr($0, 8); sub(/^[ \t]+/, "", r); if (r != "") print r }' \
    | LC_ALL=C awk '{ l[NR] = $0 } END { s = 1; while (s <= NR && l[s] ~ /^[ \t]*$/) s++; for (i = s; i <= NR; i++) print l[i] }')"
  if [ "$channel" = file ]; then
    [ -n "$filed" ] || die "$id has no answer in the file"
    text="$filed"
  elif [ -n "$filed" ] && [ "$filed" != "$text" ]; then
    die "$id already has a different answer in the file ('$(printf '%s' "$filed" | head -n 1)'); record neither, write both on a Conflict: line and ask the operator"
  fi
  # The answer goes through the environment: awk -v would expand backslashes in it.
  item="$(printf '%s\n' "$block" | STAMP="$(now_stamp)" CH="$channel" ANS="$text" LC_ALL=C awk '
    NR == 1 { sub(/ · OPEN · /, " · ANSWERED · ") }
    function answer(   n, a, i) {
      n = split(ENVIRON["ANS"], a, "\n")
      printf "Answer: %s (%s) %s\n", ENVIRON["STAMP"], ENVIRON["CH"], a[1]
      for (i = 2; i <= n; i++) print a[i]
      done = 1
    }
    /^Answer:/ { answer(); exit }
    { print }
    END { if (!done) answer() }')"
  # Archive first: a crash before the swap leaves the item in both files, and a rerun skips
  # the archive copy it already holds.
  rewrite_item "$id" 'in_item { next } { print }'
  if has_item "$ARCHIVE" "$id"; then
    # An interrupted record left an archive copy. Finish only when it holds this same answer.
    local archived
    archived="$(LEDGER="$ARCHIVE" blocks "$id" | LC_ALL=C awk '
      on { print; next }
      /^Answer:/ { on = 1; sub(/^Answer: [0-9-]+ [0-9:]+ \([a-z]+\) ?/, ""); print }' | trim_trailing_blank)"
    [ "$archived" = "$(printf '%s\n' "$text" | trim_trailing_blank)" ] \
      || die "$id is already in $ARCHIVE with another answer ('$(printf '%s' "$archived" | head -n 1)'); record neither, write both on a Conflict: line and ask the operator"
  fi
  ensure_unchanged
  if ! has_item "$ARCHIVE" "$id"; then
    [ -f "$ARCHIVE" ] || printf '# Answered decisions\n' > "$ARCHIVE"
    printf '\n%s\n' "$item" >> "$ARCHIVE"
  fi
  swap_ledger "$REWRITTEN"
  echo "$id"
  report_waiting "$id"
}

# trim_trailing_blank: copy stdin to stdout without CR and without trailing blank lines.
trim_trailing_blank() {
  LC_ALL=C awk '{ sub(/\r$/, ""); l[NR] = $0 } END { n = NR; while (n > 0 && l[n] ~ /^[ \t]*$/) n--; for (i = 1; i <= n; i++) print l[i] }'
}

# has_item <file> <D<n>>
has_item() { grep -q "^## $2 · " "$1" 2>/dev/null; }

cmd_init() {
  local session="" project="" tab="" pane="" root file cur here
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --session) [ "$#" -ge 2 ] || die "--session needs a name"; session="$2"; shift 2 ;;
      --project) [ "$#" -ge 2 ] || die "--project needs a name"; project="$2"; shift 2 ;;
      --tab) [ "$#" -ge 2 ] || die "--tab needs an id"; tab="$2"; shift 2 ;;
      --pane) [ "$#" -ge 2 ] || die "--pane needs an id"; pane="$2"; shift 2 ;;
      *) die "unknown option for init: $1" ;;
    esac
  done
  [ -n "$session" ] || die "init needs --session <supervisor session name>"
  case "$SUPERVISOR_HOME" in /*) ;; *) die "SUPERVISOR_HOME must be an absolute path: $SUPERVISOR_HOME" ;; esac
  # The project is the git root; outside git, the nearest folder holding .claude (never $HOME,
  # whose .claude is the user's own), else the supervisor folder itself.
  if ! root="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"; then
    local up home
    up="$(cd "$DIR" && pwd -P)"; home="$(cd "$HOME" 2>/dev/null && pwd -P)" || home="$HOME"
    root="$up"
    while [ "$up" != / ] && [ "$up" != "$home" ]; do
      if [ -d "$up/.claude" ]; then root="$up"; break; fi
      up="$(dirname "$up")"
    done
  fi
  root="$(cd "$root" && pwd -P)"
  [ -n "$project" ] || project="${root##*/}"
  file="$SUPERVISOR_HOME/${project//\//-}--${session//\//-}.md"
  if [ -z "$tab" ] || [ -z "$pane" ]; then
    here="$(herdr pane current 2>/dev/null)" || true
    [ -n "$tab" ] || tab="$(printf '%s' "$here" | json_field tab_id)"
    [ -n "$pane" ] || pane="$(printf '%s' "$here" | json_field pane_id)"
  fi
  mkdir -p "$SUPERVISOR_HOME"
  if [ -f "$file" ]; then
    cur="$(sed -n 's/^Project: .* · //p' "$file" | head -n 1)"
    [ "$cur" = "$root" ] || die "$file belongs to ${cur:-an unknown project}, not $root; pass another --session or --project"
    cur="$(sed -n 's/^Folder: //p' "$file" | head -n 1)"
    [ -z "$cur" ] || [ "$cur" = "$DIR" ] || die "$file belongs to the supervisor folder $cur, not $DIR; pass another --session"
  fi

  local header src=""
  header="# Pending decisions
Project: $project · $root
Supervisor: $session · Herdr tab ${tab:-unknown} · pane ${pane:-unknown}
Folder: $DIR
Started: $(now_stamp) · Archive: $ARCHIVE"

  # The ledger to migrate: an old in-project one, or the final ledger of a closed supervisor
  # that is starting again, so its OPEN items are asked again under the same numbers.
  if [ -f "$OLD_LEDGER" ]; then src="$OLD_LEDGER"
  elif [ "${LEDGER#"$DIR"/pending-decisions.final}" != "$LEDGER" ] && [ -f "$LEDGER" ]; then src="$LEDGER"
  fi

  if [ -n "$src" ]; then
    # Build the shared file and the archive first and rename the old file last, so a failure
    # leaves it in place and a rerun duplicates nothing.
    if pid_alive; then cmd_stop >&2; fi
    LEDGER="$src"
    parse_checked > /dev/null || exit $?
    take_snapshot
    local records open_ids="" done_ids="" waiting="" id st ans shared_new archive_new
    records="$(LEDGER="$SNAP" parse)"
    while IFS=$'\t' read -r id st _ ans _; do
      [ -n "$id" ] || continue
      if [ "$st" = OPEN ]; then
        has_item "$file" "$id" || open_ids="$open_ids $id"
        [ "$ans" = 0 ] || waiting="$waiting${waiting:+, }$id"
      else
        has_item "$ARCHIVE" "$id" || done_ids="$done_ids $id"
      fi
    done <<< "$records"
    shared_new="$(mktemp "$SUPERVISOR_HOME/.pending-new.XXXXXX")"; TEMPS+=("$shared_new")
    {
      if [ -f "$file" ]; then trim_trailing_blank < "$file"; else printf '%s\n' "$header"; fi
      [ -z "$open_ids" ] || { echo; LEDGER="$SNAP" blocks "$open_ids"; }
    } > "$shared_new"
    if [ -n "$done_ids" ]; then
      archive_new="$(mktemp "$DIR/.pending-new.XXXXXX")"; TEMPS+=("$archive_new")
      {
        if [ -f "$ARCHIVE" ]; then trim_trailing_blank < "$ARCHIVE"; else echo "# Answered decisions"; fi
        echo
        LEDGER="$SNAP" blocks "$done_ids"
      } > "$archive_new"
    fi
    ensure_unchanged
    [ -z "$done_ids" ] || mv "$archive_new" "$ARCHIVE"
    mv "$shared_new" "$file"
    mv "$src" "$src.migrated"
    echo "pending-watch: migrated $src: $(printf '%s' "$open_ids" | wc -w | tr -d ' ') OPEN item(s) to $file, $(printf '%s' "$done_ids" | wc -w | tr -d ' ') ANSWERED item(s) to $ARCHIVE; old file kept as $src.migrated" >&2
    [ -z "$waiting" ] || echo "pending-watch: answered but not recorded yet: $waiting (run answers, then record)" >&2
  elif [ ! -f "$file" ]; then
    local fresh
    fresh="$(mktemp "$SUPERVISOR_HOME/.pending-new.XXXXXX")"; TEMPS+=("$fresh")
    trap cleanup_temps EXIT
    printf '%s\n' "$header" > "$fresh"
    mv "$fresh" "$file"
  fi

  printf '%s\n' "$file" > "$DIR/ledger.path"
  LEDGER="$file"
  mkdir -p "$STATE"
  ledger_hash > "$STATE/hash"
  echo "$file"
}

cmd_close() {
  local final="$DIR/pending-decisions.final.md"
  if pid_alive; then cmd_stop >&2; fi
  if [ "$LEDGER" = "$final" ] || [ "${LEDGER#"$DIR"/pending-decisions.final}" != "$LEDGER" ]; then
    [ -f "$LEDGER" ] || die "no ledger at $LEDGER"
    echo "$LEDGER"; return 0
  fi
  [ -f "$LEDGER" ] || die "no ledger at $LEDGER"
  [ ! -e "$final" ] || final="$DIR/pending-decisions.final-$(date '+%Y%m%d-%H%M%S').md"
  mv "$LEDGER" "$final"
  printf '%s\n' "$final" > "$DIR/ledger.path"
  LEDGER="$final"
  mkdir -p "$STATE"
  ledger_hash > "$STATE/hash"
  echo "$final"
}

# Accepting the current file as the supervisor's own could hide an answer the operator
# saved just before, so synced lists every answer that is still waiting to be recorded.
cmd_synced() {
  local id
  mkdir -p "$STATE"
  ledger_hash > "$STATE/hash"
  parse | awk -F'\t' '$1 != "MALFORMED" && $2 == "OPEN" && $4 == 1 { print $1 }' | while IFS= read -r id; do
    echo "pending-watch: $id has an answer in the file that is not recorded yet"
  done
}

# Answers the operator gave in the file that the supervisor has not recorded yet.
cmd_answers() {
  local records ids
  records="$(parse_checked)" || exit $?
  ids="$(printf '%s\n' "$records" | awk -F'\t' '$2 == "OPEN" && $4 == 1 { printf "%s ", $1 }')"
  [ -z "$ids" ] || blocks "$ids"
}

cmd_list() {
  local records
  records="$(parse_checked)" || exit $?
  printf '%s\n' "$records" | awk -F'\t' '$2 == "OPEN" {
    state = $4 == 1 ? "answered" : ($3 == 1 ? "seen" : "unseen")
    print $1 " · " $6 " · " state " · " $5
  }'
}

cmd_line() {
  local records ids="" n=0 id acts="" na=0 out=""
  records="$(parse_checked)" || exit $?
  while IFS=$'\t' read -r id _; do
    [ -n "$id" ] || continue
    n=$((n + 1))
    if [ -f "$STATE/notified/$id" ]; then ids="$ids${ids:+, }$id"; else ids="$ids${ids:+, }$id mới"; fi
  done < <(printf '%s\n' "$records" | select_counted)
  while IFS=$'\t' read -r id _; do
    [ -n "$id" ] || continue
    na=$((na + 1)); acts="$acts${acts:+, }$id"
  done < <(action_records | awk -F'\t' '$2 == "OPEN"')
  # Actions come first so that a line with decisions still ends with "(watcher off)".
  [ "$na" -eq 0 ] || out="🛠 $na việc bạn cần tự làm ($acts) → $ACTIONS"
  if [ "$n" -gt 0 ]; then
    local off=""
    pid_alive || off=" (watcher off)"
    out="$out${out:+ · }⏳ $n đang chờ bạn ($ids) → $LEDGER$off"
  fi
  [ -z "$out" ] || echo "$out"
}

cmd_stop() {
  local pid
  if [ -f "$STATE/pid" ]; then
    pid="$(cat "$STATE/pid")"
    if pid_alive; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 1 25); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
      if kill -0 "$pid" 2>/dev/null; then
        echo "pending-watch: pid $pid ignored TERM; sending KILL" >&2
        kill -KILL "$pid" 2>/dev/null || true
      fi
      echo "pending-watch: stopped pid $pid"
    else
      echo "pending-watch: pid $pid is not a running watcher; removed the stale record"
    fi
    rm -f "$STATE/pid"
  else
    echo "pending-watch: no watcher recorded in $STATE"
  fi
  restore_label
}

cmd_watch() {
  local tab="" base=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tab) [ "$#" -ge 2 ] || die "--tab needs an id"; tab="$2"; shift 2 ;;
      --base-label) [ "$#" -ge 2 ] || die "--base-label needs a label"; base="$2"; shift 2 ;;
      *) die "unknown option for watch: $1" ;;
    esac
  done
  [ -f "$LEDGER" ] || die "no ledger at $LEDGER; run init before starting the watcher"
  mkdir -p "$STATE/notified"
  if pid_alive && [ "$(cat "$STATE/pid")" != "$$" ]; then
    die "a watcher is already running for $DIR (pid $(cat "$STATE/pid")); stop it first"
  fi

  if [ -z "$tab" ]; then
    tab="$(herdr pane current 2>/dev/null | json_field tab_id)" || true
    [ -n "$tab" ] || die "cannot resolve the Herdr tab (herdr pane current failed); pass --tab"
  fi
  if [ -z "$base" ]; then
    base="$(herdr tab get "$tab" 2>/dev/null | json_field label)" || true
    # A crashed watcher may have left its badge on the label.
    base="$(printf '%s' "$base" | sed -E 's/ (⏳|\\u23f3)[0-9]+$//')"
    [ -n "$base" ] || die "cannot read the label of tab $tab (herdr tab get failed); pass --base-label"
  fi
  printf '%s' "$tab" > "$STATE/tab"
  printf '%s' "$base" > "$STATE/base-label"
  echo "$$" > "$STATE/pid"
  [ -f "$STATE/hash" ] || ledger_hash > "$STATE/hash"
  local owner
  owner="$(find_owner)" || true
  printf '%s' "$owner" > "$STATE/owner"

  local sleeper=""
  on_exit() {
    [ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null || true
    restore_label
    if [ -f "$STATE/pid" ] && [ "$(cat "$STATE/pid")" = "$$" ]; then rm -f "$STATE/pid"; fi
  }
  trap on_exit EXIT
  trap 'exit 143' TERM
  trap 'exit 130' INT

  echo "pending-watch: watching $LEDGER (tab $tab, base label '$base', pid $$, owner ${owner:-none})"
  if [ "$(uname -s)" = Darwin ] && ! command -v terminal-notifier >/dev/null 2>&1; then
    echo "pending-watch: terminal-notifier not found, so notifications cannot open the ledger on click (brew install terminal-notifier)"
  fi
  local label="" candidate="" warned="" h now id q last n new_label records bad
  while :; do
    if [ -n "$owner" ] && ! { kill -0 "$owner" 2>/dev/null && is_claude "$owner"; }; then
      echo "pending-watch: owner gone (pid $owner)"
      exit 0
    fi
    h="$(ledger_hash)"
    if [ "$h" != "$(cat "$STATE/hash" 2>/dev/null)" ]; then
      if [ -n "$candidate" ] && [ "$h" = "$candidate" ]; then
        echo "pending-watch: user-edit"
        printf '%s\n' "pending-watch: next, in order:" \
          "  1. $(run_line answers)" \
          "  2. $(run_line record) D<n> file   # once for each item answers printed" \
          "  3. $(run_line synced)" \
          "  4. $(run_line watch)   # with run_in_background"
        exit 0
      fi
      candidate="$h"
    else
      candidate=""
    fi

    records="$(parse)"
    bad="$(printf '%s\n' "$records" | select_bad)"
    if [ -n "$bad" ]; then
      while IFS= read -r q; do
        case "$warned" in *"|$q|"*) continue ;; esac
        warned="$warned|$q|"
        echo "pending-watch: malformed header '$q'" >&2
        notify malformed "⏳ pending-decisions.md" "pending-watch: malformed header '$q'"
      done <<< "$bad"
    fi

    n=0; now="$(date +%s)"
    while IFS=$'\t' read -r id q; do
      [ -n "$id" ] || continue
      n=$((n + 1))
      if [ ! -f "$STATE/notified/$id" ]; then
        notify "$id" "⏳ $id mới" "$q"
        echo "$now" > "$STATE/notified/$id"
      else
        last="$(cat "$STATE/notified/$id")"
        if [ $((now - last)) -ge "$RENOTIFY" ]; then
          notify "$id" "⏳ $id vẫn chờ" "$q"
          echo "$now" > "$STATE/notified/$id"
        fi
      fi
    done < <(printf '%s\n' "$records" | select_counted)

    if [ "$n" -gt 0 ]; then new_label="$base ⏳$n"; else new_label="$base"; fi
    if [ "$new_label" != "$label" ]; then
      herdr tab rename "$tab" "$new_label" >/dev/null 2>&1 || echo "pending-watch: herdr tab rename failed" >&2
      label="$new_label"
    fi

    sleep "$POLL" & sleeper=$!
    wait "$sleeper" || true
    sleeper=""
  done
}

case "$cmd" in
  watch) cmd_watch "$@" ;;
  synced) cmd_synced ;;
  answers) cmd_answers ;;
  list) cmd_list ;;
  add) cmd_add "$@" ;;
  record) cmd_record "$@" ;;
  seen) cmd_seen "$@" ;;
  init) cmd_init "$@" ;;
  close) cmd_close ;;
  line) cmd_line ;;
  stop) cmd_stop ;;
  action-add) cmd_action_add "$@" ;;
  action-done) cmd_action_done "$@" ;;
  action-list) cmd_action_list ;;
  *) usage >&2; exit 2 ;;
esac
