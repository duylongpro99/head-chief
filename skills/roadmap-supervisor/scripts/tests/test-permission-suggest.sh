#!/usr/bin/env bash
# Tests for permission-suggest.py against a temporary log and settings. No model, no real settings.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PS=(python3 -I "$HERE/../permission-suggest.py")
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/permission-suggest-test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
# Never touch the operator's real files.
export PERMISSION_LOG="$ROOT/log.jsonl" CLAUDE_USER_SETTINGS="$ROOT/settings.json" PROJECT_ALLOW_FILE="$ROOT/project-allow.json"
echo '{"permissions":{"allow":["Bash(herdr agent get:*)"]},"model":"opus"}' > "$CLAUDE_USER_SETTINGS"
D="$ROOT/sup"; mkdir -p "$D"

pass=0; total=0
check() { total=$((total + 1)); if [ "$2" -eq 0 ]; then pass=$((pass + 1)); echo "ok   - $1"; else echo "FAIL - $1"; [ -z "${3:-}" ] || printf '       %s\n' "$3"; fi; }

hook() { # hook <pane> <tool> [command]
  local input
  input="$(jq -nc --arg t "$2" --arg c "${3:-}" '{session_id:"s1",cwd:"/p",hook_event_name:"PermissionRequest",tool_name:$t,tool_input:(if $c=="" then {} else {command:$c} end)}')"
  printf '%s' "$input" | HERDR_PANE_ID="$1" "${PS[@]}" log
}
times() { local n="$1"; shift; for _ in $(seq "$n"); do hook "$@"; done; }

# --- log
out="$(hook W:p1 Bash 'herdr tab get W:t1')"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ]; check "log prints nothing and exits 0" $? "rc=$rc out=$out"
[ "$(wc -l < "$PERMISSION_LOG" | tr -d ' ')" = 1 ] && jq -e '.pane=="W:p1" and .tool=="Bash" and .command=="herdr tab get W:t1"' "$PERMISSION_LOG" >/dev/null
check "log writes one line with pane, tool and command" $?
[ "$(stat -f %Lp "$PERMISSION_LOG" 2>/dev/null || stat -c %a "$PERMISSION_LOG")" = 600 ]; check "log file is private (600)" $?
out="$(printf 'not json' | "${PS[@]}" log)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ]; check "log ignores bad input and still exits 0" $?

# --- suggest: below threshold is silent
times 1 W:p2 Bash 'herdr tab get W:t2'
out="$("${PS[@]}" suggest "$D")"
[ -z "$out" ]; check "suggest is silent when nothing reaches the threshold" $? "$out"

# --- build the log
times 2 W:p2 Bash 'herdr tab get W:t3 2>/dev/null'                       # -> herdr tab get (4 total)
times 3 W:p3 Bash "bash /work/proj/scripts/build.sh --fast"              # project script
times 3 W:p3 Bash 'cd /p && npm test -- --watch=false'                    # compound, cd ignored
times 3 W:p3 Bash 'rm -rf build'                                         # denied command
times 3 W:p3 Bash 'curl https://example.com'                             # off the machine
times 3 W:p3 Bash 'herdr pane run W:p1 ls'                               # denied prefix
times 3 W:p3 Bash 'cat .env'                                             # secret file
times 3 W:p3 Bash 'git -C /p status'                                     # bare git would be too broad
times 3 W:p3 Bash 'herdr agent get W:p1'                                 # already allowed
times 3 W:p3 Bash '/tmp/x/run.sh'                                        # temp dir
times 3 W:p3 Bash 'ls > out.txt'                                         # writes a file
times 3 W:p3 Bash 'echo $(whoami)'                                       # substitution
times 3 W:p3 mcp__linear__list_issues
times 3 W:p3 mcp__linear__delete_issue
times 3 W:p3 Edit

out="$("${PS[@]}" suggest "$D")"; rc=$?
item="$(printf '%s\n' "$out" | head -1)"
[ "$rc" -eq 0 ] && [ -f "$item" ]; check "suggest writes a ledger item and prints its path first" $? "$out"
has() { printf '%s\n' "$out" | grep -qF -- "$1"; }
has '(global): Bash(herdr tab get:*) — 4 lần, pane W:p1, W:p2'; check "global rule from a herdr read, counted across panes since the dir was made" $? "$out"
has "(project): Bash(bash /work/proj/scripts/build.sh:*)"; check "project rule for a script path" $? "$out"
has '(global): Bash(npm test:*)'; check "compound command is split and cd ignored" $? "$out"
has '(global): mcp__linear__list_issues'; check "read-only MCP tool is proposed" $? "$out"
for bad in 'Bash(rm' 'Bash(curl' 'Bash(herdr pane' '.env' 'Bash(git' 'herdr agent get' '/tmp/' 'Bash(ls' 'Bash(echo' 'delete_issue' 'Edit'; do
  ! printf '%s\n' "$out" | sed 1d | grep -qF -- "$bad"; check "not proposed: $bad" $? "$out"
done
[ "$(sed -n 1p "$item")" = permissions ] && grep -q '^Câu hỏi:' "$item" && grep -q '^Chặn:' "$item"
check "item has the scope line, question and Chặn:" $?
n="$(printf '%s\n' "$out" | sed 1d | wc -l | tr -d ' ')"
[ "$n" = 4 ]; check "exactly four rules proposed" $? "got $n"

out2="$("${PS[@]}" suggest "$D")"
[ -z "$out2" ]; check "a second suggest is silent: rules proposed before are not repeated" $? "$out2"

# --- apply / decline
id_of() { jq -r --arg r "$1" '.rules[$r].id' "$D/permission-suggestions.json"; }
G="$(id_of 'Bash(herdr tab get:*)')"; P="$(id_of "Bash(bash /work/proj/scripts/build.sh:*)")"
"${PS[@]}" apply "$D" "$G" "$P" >/dev/null; rc=$?
[ "$rc" -eq 0 ] && jq -e '.permissions.allow | index("Bash(herdr tab get:*)")' "$CLAUDE_USER_SETTINGS" >/dev/null && jq -e '.model=="opus"' "$CLAUDE_USER_SETTINGS" >/dev/null
check "apply writes a global rule to user settings and keeps other keys" $?
jq -e --arg r "Bash(bash /work/proj/scripts/build.sh:*)" 'index($r)' "$PROJECT_ALLOW_FILE" >/dev/null
check "apply writes a project rule to the project allow list" $?
ls "$CLAUDE_USER_SETTINGS".bak-* >/dev/null 2>&1; check "apply backs up user settings first" $?
"${PS[@]}" apply "$D" "$G" >/dev/null 2>&1; [ $? -ne 0 ]; check "apply refuses a rule that is no longer proposed" $?
"${PS[@]}" decline "$D" all >/dev/null
[ "$(jq '[.rules[] | select(.status=="proposed")] | length' "$D/permission-suggestions.json")" = 0 ]
check "decline all clears every proposed rule" $?

times 5 W:p4 Bash 'npm test'
times 3 W:p4 Bash 'herdr pane list'
out="$("${PS[@]}" suggest "$D")"
! printf '%s\n' "$out" | grep -qF 'npm test' && printf '%s\n' "$out" | grep -qF 'Bash(herdr pane list:*)'
check "declined rules stay quiet; new ones are still proposed" $? "$out"

out="$("${PS[@]}" suggest "$D" --since "$(( $(date +%s) + 60 ))")"
[ -z "$out" ]; check "--since drops older entries" $? "$out"

echo "$pass/$total passed"
[ "$pass" -eq "$total" ]
