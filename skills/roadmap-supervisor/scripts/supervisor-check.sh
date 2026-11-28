#!/usr/bin/env bash
# supervisor-check.sh — the mechanical checks of a roadmap supervisor, without calling any model.
#
#   supervisor-check.sh setup  <dir> --repo <path> --main <branch> [--test '<command>']
#   supervisor-check.sh resume <dir>
#   supervisor-check.sh accept <dir> <item> <sha> [--merge] [--also <sha>]... [--running <sha>]...
#                              [--scope <path-or-glob>]... [--allow-dirty <path-or-glob>]...
#                              [--report <file>] [--no-tests] [--secret-ok <file>:<line>]...
#   supervisor-check.sh confirm <dir> <item>
#   supervisor-check.sh accepted <dir>
#
# setup: run once at Start. Writes <dir>/.check/conf (repository, main branch, test command),
#   and, only when they do not exist yet, <dir>/.check/status-baseline (`git status
#   --porcelain` of the main checkout: what was modified or untracked before supervision) and
#   <dir>/.check/verified-head (the main head). Run it again to change the test command.
# resume: run first on every wake-up, compaction or restart. Prints the main head and the
#   commits not checked yet, the loop state and TBD values in state.md, the sessions.md rows
#   still running and whether their panes exist, the ledger state, the open items, the
#   watcher state and the accepted items. Then "DO now" with the commands that must follow,
#   and the rules in resume-rules.txt. It changes nothing.
# accept, then confirm: the only way an item becomes done. <sha> is the commit the report cites. Checks:
#   - <sha> is on the main branch; with --merge it is also a --no-ff merge (two parents);
#   - every first-parent commit on main after the verified head is <sha>, an --also commit of
#     the same session, or a --running commit of a session that has not reported yet;
#   - every file changed by <sha> and the --also commits is inside a --scope and outside <dir>;
#   - the main checkout has no modified or untracked path beyond the baseline, <dir> and the
#     --allow-dirty paths (report paths, the write scope of a session still running on main);
#   - the test command from setup exits 0 (skipped with --no-tests, or when none was set);
#   - every `path:line` cited in --report exists on main. Those lines are printed as
#     EVIDENCE for you to compare with the report's claim;
#   - secret-scan.sh finds no likely secret in --report or in the lines this session's
#     commits added. A hit names the file, line and kind, never the value; --secret-ok skips
#     one hit you have judged a false positive.
#   All pass: prints "RESULT: CHECKS PASS", keeps the result as pending, exits 0. The item
#   is not recorded yet. Any fail: prints each FAIL, keeps nothing, exits 1.
# confirm: run it after you compared the EVIDENCE lines with the report and did the checks
#   the script cannot do. Appends the item to <dir>/accepted.tsv and moves the verified head
#   (to main, or to the commit before the earliest --running commit; the commits of this
#   session are remembered so a later accept does not ask about them again). It refuses when accept
#   did not pass for the item, or when main moved since then (run accept again).
# accepted: prints <dir>/accepted.tsv (item, commit, time, tests|no-tests).
set -uo pipefail

die() { echo "supervisor-check: $*" >&2; exit 2; }
usage() { awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
PW="$HERE/pending-watch.sh"
SCAN="$HERE/secret-scan.sh"

[ "$#" -ge 2 ] || { usage; exit 2; }
cmd="$1"; DIR="$2"; shift 2
[ -d "$DIR" ] || die "no such folder: $DIR"
DIR="$(cd "$DIR" && pwd -P)"
CHECK="$DIR/.check"

q() { printf '%q' "$1"; }

load_conf() {
  [ -f "$CHECK/conf" ] || die "no $CHECK/conf; run: $(q "$SELF") setup $(q "$DIR") --repo <path> --main <branch> [--test '<command>']"
  REPO="$(sed -n 's/^repo=//p' "$CHECK/conf")"
  MAIN="$(sed -n 's/^main=//p' "$CHECK/conf")"
  TESTCMD="$(sed -n 's/^test=//p' "$CHECK/conf")"
  git -C "$REPO" rev-parse --verify -q "$MAIN^{commit}" > /dev/null || die "branch $MAIN not found in $REPO"
  # <dir> relative to the repository, when it lies inside it.
  REL=""
  case "$DIR/" in "$REPO"/*) REL="${DIR#"$REPO"/}" ;; esac
}

# matches <path> <pattern>...: the path equals a pattern, lies under it, or matches it as a glob.
matches() {
  local f="$1" p; shift
  for p in "$@"; do
    p="${p%/}"
    [ -n "$p" ] || continue
    # shellcheck disable=SC2053
    if [ "$f" = "$p" ] || [[ "$f" == "$p"/* ]] || [[ "$f" == $p ]]; then return 0; fi
  done
  return 1
}

cmd_setup() {
  local repo="" main="" test="" have_test=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --main) main="${2:-}"; shift 2 ;;
      --test) test="${2:-}"; have_test=1; shift 2 ;;
      *) die "setup: unknown argument $1" ;;
    esac
  done
  [ -n "$repo" ] && [ -n "$main" ] || die "usage: setup <dir> --repo <path> --main <branch> [--test '<command>']"
  repo="$(cd "$repo" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || die "setup: not a git repository: $repo"
  repo="$(cd "$repo" && pwd -P)"
  git -C "$repo" rev-parse --verify -q "$main^{commit}" > /dev/null || die "setup: branch $main not found in $repo"
  case "$test" in *$'\n'*) die "setup: the test command must be one line" ;; esac
  mkdir -p "$CHECK"
  if [ "$have_test" -eq 0 ] && [ -f "$CHECK/conf" ]; then test="$(sed -n 's/^test=//p' "$CHECK/conf")"; fi
  printf 'repo=%s\nmain=%s\ntest=%s\n' "$repo" "$main" "$test" > "$CHECK/conf"
  [ -f "$CHECK/status-baseline" ] || git -C "$repo" status --porcelain > "$CHECK/status-baseline"
  [ -f "$CHECK/verified-head" ] || git -C "$repo" rev-parse "$main" > "$CHECK/verified-head"
  echo "supervisor-check: setup done"
  echo "  repository: $repo"
  echo "  main: $main at $(git -C "$repo" rev-parse --short "$(cat "$CHECK/verified-head")") (verified head)"
  echo "  test command: ${test:-none; accept will skip the tests until you run setup again with --test}"
  echo "  baseline: $(grep -c . "$CHECK/status-baseline" || true) path(s) already modified or untracked"
}

cmd_resume() {
  local n=0 do_lines=() line pane panes="" head verified count
  add_do() { n=$((n + 1)); do_lines+=("  $n. $1"); }

  echo "supervisor-check: resume $DIR"
  if [ -f "$CHECK/conf" ]; then
    load_conf
    head="$(git -C "$REPO" rev-parse "$MAIN")"
    verified="$(cat "$CHECK/verified-head" 2>/dev/null || echo "$head")"
    count="$(git -C "$REPO" rev-list --first-parent --count "$verified..$head" 2>/dev/null || echo '?')"
    echo "main: $MAIN at $(git -C "$REPO" rev-parse --short "$head"), verified up to $(git -C "$REPO" rev-parse --short "$verified" 2>/dev/null || echo '?'), $count commit(s) not checked yet"
    [ "$count" = 0 ] || git -C "$REPO" log --first-parent --format='  %h %s' "$verified..$head" 2>/dev/null | head -n 20
    echo "test command: ${TESTCMD:-none, so accept skips the tests. Once state.md has one, run setup again with --test}"
  else
    echo "main: unknown (no $CHECK/conf)"
    add_do "Run: $(q "$SELF") setup $(q "$DIR") --repo <path> --main <branch> [--test '<command>']"
  fi

  if [ -f "$DIR/state.md" ]; then
    # Only the Config part counts: Items and Decisions may mention "loop:" or "TBD" in prose.
    local config
    config="$(awk '/^## / { on = ($0 ~ /^## Config/) } on' "$DIR/state.md")"
    [ -n "$config" ] || { echo "state.md: no \"## Config\" heading; reading the whole file"; config="$(cat "$DIR/state.md")"; }
    line="$(printf '%s\n' "$config" | grep -o 'loop: [a-z]*' | tail -n 1)"
    echo "${line:-loop: not recorded in state.md Config}"
    if printf '%s\n' "$config" | grep -q 'TBD'; then
      echo "state.md Config: has TBD value(s)"
      add_do "Settle the TBD values: steps 14 to 17 of references/start.md. Open no session before that."
    fi
    case "$line" in "loop: paused") PAUSED=1 ;; *) PAUSED=0 ;; esac
  else
    echo "state.md: MISSING"; PAUSED=0
    add_do "No state.md: see the end of the Resume section in SKILL.md."
  fi

  echo "sessions.md rows still running:"
  local rows="" have_panes=0
  # A row is running when one of its cells starts with "running" (the status column).
  [ -f "$DIR/sessions.md" ] && rows="$(awk -F'|' '{ for (i = 1; i <= NF; i++) { c = $i; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c ~ /^running/) { print; next } } }' "$DIR/sessions.md")"
  if [ -n "$rows" ]; then
    if command -v herdr > /dev/null 2>&1 && panes="$(herdr pane list 2>/dev/null)" && [ -n "$panes" ]; then have_panes=1; fi
    [ "$have_panes" -eq 1 ] || echo "  (herdr pane list is unavailable: check each pane yourself with herdr agent get <pane>)"
    while IFS= read -r line; do
      echo "  $line"
      [ "$have_panes" -eq 1 ] || continue
      pane="$(printf '%s\n' "$line" | grep -oE '[A-Za-z0-9]+:p[A-Za-z0-9]+' | head -n 1)"
      [ -n "$pane" ] || continue
      if printf '%s\n' "$panes" | grep -qwF -- "$pane"; then echo "    pane $pane: open"
      else
        echo "    pane $pane: NOT in herdr pane list"
        add_do "Check pane $pane with herdr agent get. If it is gone, follow \"Gone, or cannot continue\" in the reference."
      fi
    done <<< "$rows"
  else
    echo "  none"
  fi

  local ledger="" lp_ok=1 out
  [ -f "$DIR/ledger.path" ] && ledger="$(cat "$DIR/ledger.path")"
  case "$ledger" in ""|*pending-decisions.final.md) lp_ok=0 ;; esac
  if [ "$lp_ok" -eq 0 ]; then
    echo "ledger: not live"
    add_do "Run: $(q "$PW") init $(q "$DIR") --session <this session's name>, then record any answer it names."
  else
    echo "open items:"
    out="$("$PW" list "$DIR" 2>&1)" || true
    if [ -n "$out" ]; then printf '%s\n' "$out" | sed 's/^/  /'; else echo "  none"; fi
    out="$("$PW" answers "$DIR" 2>/dev/null)" || true
    if [ -n "$out" ]; then
      echo "answers waiting in the file:"; printf '%s\n' "$out" | sed 's/^/  /'
      add_do "Record each answer above: $(q "$PW") record $(q "$DIR") D<n> file, then $(q "$PW") synced $(q "$DIR")."
    fi
    local pid=""
    [ -f "$DIR/.pending-state/pid" ] && pid="$(cat "$DIR/.pending-state/pid")"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "watcher: running (pid $pid)"
    else
      echo "watcher: OFF"
      add_do "After recording any answer above, run $(q "$PW") synced $(q "$DIR"), then start with run_in_background: $(q "$PW") watch $(q "$DIR")"
    fi
  fi

  echo "accepted items (done only when listed here):"
  if [ -s "$DIR/accepted.tsv" ]; then sed 's/^/  /' "$DIR/accepted.tsv"; else echo "  none"; fi

  echo "operator actions still open (in $DIR/operator-actions.md):"
  out="$("$PW" action-list "$DIR" 2>&1)" || true
  if [ -n "$out" ]; then printf '%s\n' "$out" | sed 's/^/  /'; else echo "  none"; fi

  add_do "Run ListAgents: a session listed there but not in sessions.md is not yours."
  if [ "${PAUSED:-0}" -eq 1 ]; then
    add_do "The loop is paused: if no new answer unblocks an item, schedule no wake-up and end the turn."
  fi
  add_do "Continue with \"On each wake-up or message\" in references/monitoring-and-operator-gate.md (read it first if its text is not in this conversation)."
  echo "DO now, in order:"
  printf '%s\n' "${do_lines[@]}"
  if [ -f "$HERE/resume-rules.txt" ]; then
    echo "Rules that were broken before:"
    sed -e '/^[[:space:]]*$/d' -e 's/^/  - /' "$HERE/resume-rules.txt"
  fi
}

cmd_accept() {
  [ "$#" -ge 2 ] || die "usage: accept <dir> <item> <sha> [options]"
  local item="$1" sha="$2"; shift 2
  local merge=0 notests=0 report="" also=() running=() scope=() dirty=() secret_ok=() fails=() f c
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --merge) merge=1; shift ;;
      --no-tests) notests=1; shift ;;
      --also) also+=("${2:-}"); shift 2 ;;
      --running) running+=("${2:-}"); shift 2 ;;
      --scope) scope+=("${2:-}"); shift 2 ;;
      --allow-dirty) dirty+=("${2:-}"); shift 2 ;;
      --report) report="${2:-}"; shift 2 ;;
      --secret-ok) secret_ok+=("${2:-}"); shift 2 ;;
      *) die "accept: unknown argument $1" ;;
    esac
  done
  case "$item" in *$'\t'*|*/*|"") die "accept: bad item name" ;; esac
  load_conf
  [ -z "$report" ] || [ -f "$report" ] || die "accept: no such report file: $report"
  bad() { fails+=("$1"); echo "FAIL  $1"; }
  good() { echo "ok    $1"; }
  full() { git -C "$REPO" rev-parse --verify -q "$1^{commit}" 2>/dev/null; }

  echo "supervisor-check: accept $item at $sha"
  local head verified fsha
  head="$(git -C "$REPO" rev-parse "$MAIN")"
  verified="$(cat "$CHECK/verified-head" 2>/dev/null || true)"
  fsha="$(full "$sha")" || { bad "commit $sha does not exist in $REPO"; fsha=""; }

  # 1. On main, and a --no-ff merge when the report says "merged".
  local mine=() x fx
  if [ -n "$fsha" ]; then
    mine+=("$fsha")
    if git -C "$REPO" merge-base --is-ancestor "$fsha" "$head"; then good "$sha is on $MAIN"
    else bad "$sha is not on $MAIN"; fi
    if [ "$merge" -eq 1 ]; then
      if [ "$(git -C "$REPO" rev-list --parents -n 1 "$fsha" | wc -w | tr -d ' ')" -eq 3 ]; then good "$sha is a --no-ff merge"
      else bad "$sha is not a merge commit with two parents"; fi
    fi
  fi
  for x in ${also[@]+"${also[@]}"}; do
    if fx="$(full "$x")"; then
      mine+=("$fx")
      git -C "$REPO" merge-base --is-ancestor "$fx" "$head" || bad "--also $x is not on $MAIN"
    else bad "--also commit $x does not exist"; fi
  done
  local others=() earliest=""
  for x in ${running[@]+"${running[@]}"}; do
    if fx="$(full "$x")"; then others+=("$fx"); else bad "--running commit $x does not exist"; fi
  done

  # 2. Every commit on main not checked yet belongs to a named session.
  if [ -n "$verified" ] && git -C "$REPO" merge-base --is-ancestor "$verified" "$head" 2>/dev/null; then
    local unknown=0
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      if printf '%s\n' ${mine[@]+"${mine[@]}"} | grep -qx "$c"; then continue; fi
      # A commit of a session accepted earlier, while another session's commit kept the verified head back.
      if grep -qx "$c" "$CHECK/accounted" 2>/dev/null; then continue; fi
      if printf '%s\n' ${others[@]+"${others[@]}"} | grep -qx "$c"; then earliest="$c"; continue; fi
      unknown=1
      bad "commit $(git -C "$REPO" log -1 --format='%h %s' "$c") is on $MAIN after the verified head and belongs to no named session (pass --also if this session made it, --running if a session that has not reported yet made it; otherwise it goes to the operator)"
    done < <(git -C "$REPO" rev-list --first-parent "$verified..$head")
    [ "$unknown" -eq 1 ] || good "every commit on $MAIN after the verified head is accounted for"
  else
    bad "the verified head ${verified:-<none>} is not an ancestor of $MAIN (history was rewritten, or setup never ran); tell the operator"
  fi

  # 3. Write scope of this session's commits.
  local changed="" outside=0
  for c in ${mine[@]+"${mine[@]}"}; do
    if [ "$(git -C "$REPO" rev-list --parents -n 1 "$c" | wc -w | tr -d ' ')" -ge 3 ]; then
      changed+="$(git -C "$REPO" diff --no-renames --name-only "$c^1" "$c")"$'\n'
    else
      changed+="$(git -C "$REPO" show --no-renames --name-only --format= "$c")"$'\n'
    fi
  done
  changed="$(printf '%s' "$changed" | sed '/^$/d' | sort -u)"
  if [ "${#scope[@]}" -eq 0 ]; then
    bad "no --scope given: pass the write scope from the session's brief"
  else
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ -n "$REL" ] && matches "$f" "$REL"; then outside=1; bad "changed a file in the supervisor folder: $f"
      elif ! matches "$f" "${scope[@]}"; then outside=1; bad "changed a file outside the write scope: $f"; fi
    done <<< "$changed"
    [ "$outside" -eq 1 ] || good "$(printf '%s\n' "$changed" | grep -c . || true) changed file(s), all inside the write scope"
  fi

  # 4. Main checkout clean, compared with the baseline.
  local dirtybad=0 path
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    grep -qxF -- "$line" "$CHECK/status-baseline" 2>/dev/null && continue
    path="${line:3}"; path="${path##* -> }"; path="${path%\"}"; path="${path#\"}"
    if [ -n "$REL" ] && matches "${path%/}" "$REL"; then continue; fi
    # An untracked folder is listed once ("?? plans/"): accept it when the supervisor folder is inside.
    if [ -n "$REL" ] && [[ "$REL/" == "$path"* ]] && [[ "$path" == */ ]]; then continue; fi
    if [ "${#dirty[@]}" -gt 0 ] && matches "${path%/}" "${dirty[@]}"; then continue; fi
    dirtybad=1; bad "main checkout is not clean: $line"
  done < <(git -C "$REPO" status --porcelain)
  [ "$dirtybad" -eq 1 ] || good "main checkout is clean (beyond the baseline)"

  # 5. Tests.
  local tests="no-tests" out rc
  if [ "$notests" -eq 1 ]; then echo "skip  tests (--no-tests)"
  elif [ -z "$TESTCMD" ]; then echo "skip  tests (no test command; run setup with --test)"
  elif [ "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" != "$MAIN" ]; then
    bad "the checkout at $REPO is not on $MAIN, so the tests would not run on main"
  else
    out="$(cd "$REPO" && bash -c "$TESTCMD" 2>&1)"; rc=$?
    printf '%s\n' "$out" | tail -n 15 | sed 's/^/      | /'
    if [ "$rc" -eq 0 ]; then good "test command exited 0 (compare the count above with the baseline in state.md)"; tests="tests"
    else bad "test command exited $rc"; fi
  fi

  # 6. Evidence for the lines the report cites.
  if [ -n "$report" ]; then
    local cites cite cf cl shown=0
    cites="$(grep -oE '[A-Za-z0-9_./@~+-]+\.[A-Za-z0-9]+:[0-9]+' "$report" | sort -u | head -n 30)"
    if [ -n "$cites" ]; then
      echo "EVIDENCE: lines on $MAIN that the report cites. Compare each with the report's claim:"
      while IFS= read -r cite; do
        cf="${cite%:*}"; cl="${cite##*:}"; cf="${cf#./}"
        local abs=0 try
        case "$cf" in "$REPO"/*) cf="${cf#"$REPO"/}" ;; esac
        case "$cf" in /*) abs=1 ;; esac
        # A worktree path, an absolute path or a URL: drop leading parts until a file on main matches.
        try="${cf#/}"; try="${try#/}"
        while ! git -C "$REPO" cat-file -e "$head:$try" 2>/dev/null; do
          case "$try" in */*) try="${try#*/}" ;; *) try=""; break ;; esac
        done
        if [ -z "$try" ]; then
          # Only a path given relative to the repository is a claim the script can refute.
          case "$abs:$cf" in
            0:*/*) bad "cited file does not exist on $MAIN: $cite" ;;
            *) echo "      not checked: $cite (no such path on $MAIN; open it yourself)"; shown=1 ;;
          esac
          continue
        fi
        if [ "$cl" -lt 1 ] || [ "$(git -C "$REPO" show "$head:$try" | awk 'END { print NR }')" -lt "$cl" ]; then
          bad "cited line does not exist on $MAIN: $cite"; continue
        fi
        shown=1
        git -C "$REPO" show "$head:$try" | awk -v f="$try" -v n="$cl" 'NR >= n - 1 && NR <= n + 1 { printf "      %s:%d%s %s\n", f, NR, (NR == n ? ">" : " "), $0 }'
      done <<< "$cites"
      [ "$shown" -eq 1 ] || echo "      (no cited line could be shown)"
    else
      echo "EVIDENCE: the report cites no file:line."
    fi
  fi

  # 7. Secrets in the report and in what this session added to main. Never print the value.
  local hits="" hit where
  [ -z "$report" ] || hits="$("$SCAN" "$report" 2>&1)"
  for c in ${mine[@]+"${mine[@]}"}; do
    if [ "$(git -C "$REPO" rev-list --parents -n 1 "$c" | wc -w | tr -d ' ')" -ge 3 ]; then
      hits+=$'\n'"$(git -C "$REPO" diff --no-renames -U0 "$c^1" "$c" | "$SCAN" --diff 2>&1)"
    else
      hits+=$'\n'"$(git -C "$REPO" show --no-renames -U0 --format= "$c" | "$SCAN" --diff 2>&1)"
    fi
  done
  local secretbad=0
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    where="${hit%: *}"
    if [ "${#secret_ok[@]}" -gt 0 ] && printf '%s\n' "${secret_ok[@]}" | grep -qxF -- "$where"; then
      echo "skip  possible secret at $where (--secret-ok)"; continue
    fi
    secretbad=1
    bad "possible secret ($( printf '%s' "$hit" | sed 's/.*: //')) at $where; the value is not shown. Do not print it. If it may be real, it goes to the operator (rotate it, and whether to remove it from history). Only a clear false positive: run accept again with --secret-ok $where"
  done < <(printf '%s\n' "$hits" | sort -u)
  [ "$secretbad" -eq 1 ] || good "no likely secret in the report or in the lines this session added"

  if [ "${#fails[@]}" -gt 0 ]; then
    rm -f "$CHECK/pending/$item"
    echo "RESULT: FAIL (${#fails[@]}). $item is NOT done. Nothing was recorded."
    echo "Next: follow \"A report that fails a check\" in references/monitoring-and-operator-gate.md."
    exit 1
  fi
  local newv="$head"
  [ -z "$earliest" ] || newv="$(git -C "$REPO" rev-parse "$earliest^")"
  mkdir -p "$CHECK/pending"
  printf 'head=%s\nsha=%s\nverified=%s\ntests=%s\nmine=%s\n' "$head" "$(git -C "$REPO" rev-parse --short "$fsha")" "$newv" "$tests" "${mine[*]}" > "$CHECK/pending/$item"
  echo "RESULT: CHECKS PASS. $item is NOT recorded yet."
  echo "Next, in order:"
  echo "  1. Compare every EVIDENCE line above with what the report claims about it. A mismatch fails the report."
  echo "  2. Do the checks the script cannot do: a config value read from the real file, the test count against the baseline, the roadmap row or phase status, worktree and branch removed, processes stopped."
  echo "  3. Only when all of that holds: $(q "$SELF") confirm $(q "$DIR") $(q "$item")"
  echo "  If something does not hold, do not confirm: follow \"A report that fails a check\" in references/monitoring-and-operator-gate.md."
}

cmd_confirm() {
  [ "$#" -eq 1 ] || die "usage: confirm <dir> <item>"
  local item="$1" p="$CHECK/pending/$1" head
  case "$item" in */*|"") die "confirm: bad item name" ;; esac
  load_conf
  [ -f "$p" ] || { echo "supervisor-check: accept has not passed for $item; run accept first" >&2; exit 1; }
  head="$(git -C "$REPO" rev-parse "$MAIN")"
  if [ "$(sed -n 's/^head=//p' "$p")" != "$head" ]; then
    rm -f "$p"
    echo "supervisor-check: $MAIN moved since accept passed for $item; run accept again" >&2; exit 1
  fi
  sed -n 's/^verified=//p' "$p" > "$CHECK/verified-head"
  sed -n 's/^mine=//p' "$p" | tr ' ' '\n' | sed '/^$/d' >> "$CHECK/accounted"
  printf '%s\t%s\t%s\t%s\n' "$item" "$(sed -n 's/^sha=//p' "$p")" "$(date '+%Y-%m-%d %H:%M')" "$(sed -n 's/^tests=//p' "$p")" >> "$DIR/accepted.tsv"
  rm -f "$p"
  echo "supervisor-check: $item recorded in accepted.tsv; verified head is now $(git -C "$REPO" rev-parse --short "$(cat "$CHECK/verified-head")"). Now mark $item done in state.md."
}

cmd_accepted() { [ -s "$DIR/accepted.tsv" ] && cat "$DIR/accepted.tsv"; return 0; }

case "$cmd" in
  setup) cmd_setup "$@" ;;
  resume) cmd_resume ;;
  accept) cmd_accept "$@" ;;
  confirm) cmd_confirm "$@" ;;
  accepted) cmd_accepted ;;
  *) usage; exit 2 ;;
esac
