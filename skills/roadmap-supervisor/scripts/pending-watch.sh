#!/usr/bin/env bash
# pending-watch.sh — watch a supervisor's pending-decisions.md ledger without calling any model.
#
#   pending-watch.sh watch  <dir> [--tab <tab-id>] [--base-label <label>]
#   pending-watch.sh synced <dir>   # run in the same Bash call as every supervisor write;
#                                   # lists answers in the file that are not recorded yet
#   pending-watch.sh answers <dir>  # full block of every OPEN item that has an answer
#   pending-watch.sh list   <dir>   # one line per OPEN item: D<n> · scope · unseen|seen|answered · question
#   pending-watch.sh line   <dir>   # one-line footer while items wait; nothing when none do
#   pending-watch.sh stop   <dir>   # stop a running watcher and restore the tab label
#
# watch: badges the Herdr tab "<base> ⏳N" (N = open, unseen items), notifies each new item
#   once and again every PENDING_RENOTIFY_SECONDS (default 1800), polls every
#   PENDING_POLL_SECONDS (default 5), and exits 0 with "pending-watch: user-edit" when the
#   ledger changes without a matching `synced` and stays unchanged for one more poll.
#   Run it with run_in_background so its exit wakes the supervisor.
#   --tab defaults to the tab of `herdr pane current`; --base-label overrides the label read
#   with `herdr tab get`.
#   Each notification is sent through Herdr and, when `terminal-notifier` is installed, also
#   as a desktop notification that opens <dir> when clicked (a Herdr notification cannot
#   carry a click action).
#   When started under a Claude Code process, it exits with "pending-watch: owner gone" once
#   that process is gone, so a crashed or closed session leaves no watcher behind.
# line, answers, list: exit 2 on a malformed "## D" header. answers prints each block from
#   its "## D" line to the next "## " line, blocks separated by one blank line.
#
# State lives in <dir>/.pending-state/ (hash, pid, owner, tab, base-label, notified/<Dn>).
# This script never writes pending-decisions.md.
set -euo pipefail

die() { echo "pending-watch: $*" >&2; exit 1; }
usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; }

notifier_warned=""
POLL="${PENDING_POLL_SECONDS:-5}"
RENOTIFY="${PENDING_RENOTIFY_SECONDS:-1800}"

[ "$#" -ge 1 ] || { usage >&2; exit 2; }
cmd="$1"; shift
case "$cmd" in -h|--help|help) usage; exit 0 ;; esac
[ "$#" -ge 1 ] || die "$cmd needs the supervisor folder"
[ -d "$1" ] || die "no such folder: $1"
DIR="$(cd "$1" && pwd -P)"; shift
LEDGER="$DIR/pending-decisions.md"
STATE="$DIR/.pending-state"

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

# file:// URL of the supervisor folder, percent-encoded byte by byte so spaces and
# non-ASCII names survive.
dir_url() {
  local LC_ALL=C s="$DIR" out="" c i n
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
# the supervisor folder. <group> makes a reminder replace the earlier notification of the
# same item instead of stacking.
notify() {
  local group="$1" title="$2" body="$3"
  herdr notification show "$title" --body "$body" --sound request >/dev/null 2>&1 || true
  command -v terminal-notifier >/dev/null 2>&1 || return 0
  # terminal-notifier reads a leading "[", "(", "<" or "-" as syntax unless it is escaped.
  case "$body" in '['*|'('*|'<'*|-*) body="\\$body" ;; esac
  # macOS shows the title and the subtitle on one line each and wraps only the message, so
  # the subtitle carries just the folder name and the full path goes on its own message line.
  local err short="$DIR"
  case "$DIR" in "$HOME"/*) short="~${DIR#"$HOME"}" ;; esac
  body="$body
📂 $short"
  if ! err="$(terminal-notifier -title "$title" -subtitle "Bấm để mở ${DIR##*/}" -message "$body" \
      -open "$(dir_url)" -group "pending-watch:$DIR:$group" 2>&1 >/dev/null </dev/null)"; then
    # Usually macOS has notifications switched off for terminal-notifier. Say so once.
    [ -n "$notifier_warned" ] || echo "pending-watch: terminal-notifier failed, no clickable notification: $err" >&2
    notifier_warned=1
  fi
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
  [ -z "$ids" ] || blocks $ids
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
  local records ids="" n=0 id
  records="$(parse_checked)" || exit $?
  while IFS=$'\t' read -r id _; do
    [ -n "$id" ] || continue
    n=$((n + 1))
    if [ -f "$STATE/notified/$id" ]; then ids="$ids${ids:+, }$id"; else ids="$ids${ids:+, }$id mới"; fi
  done < <(printf '%s\n' "$records" | select_counted)
  [ "$n" -gt 0 ] || return 0
  local off=""
  pid_alive || off=" (watcher off)"
  echo "⏳ $n đang chờ bạn ($ids) → $LEDGER$off"
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
  [ -f "$LEDGER" ] || die "no ledger at $LEDGER; create it before starting the watcher"
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
    echo "pending-watch: terminal-notifier not found, so notifications cannot open the folder on click (brew install terminal-notifier)"
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
  line) cmd_line ;;
  stop) cmd_stop ;;
  *) usage >&2; exit 2 ;;
esac
