#!/usr/bin/env bash
# Tests for permission-suggest.py against a temporary log, settings and a stub pending-watch.sh.
# No model, no real settings, no real ledger.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PS=(python3 -I "$HERE/../permission-suggest.py")
ROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/permission-suggest-test.XXXXXX")" && pwd)"
trap 'rm -rf "$ROOT"' EXIT
# Never touch the operator's real files.
# The test project lives under TMPDIR; treat only /tmp as a temp dir here.
export PERMISSION_SUGGEST_TEMP_DIRS=/tmp/
export PERMISSION_LOG="$ROOT/log.jsonl" PROJECT_ALLOW_FILE="$ROOT/project-allow.json"
mkdir -p "$ROOT/dotfiles"
echo '{"permissions":{"allow":["Bash(herdr agent get:*)"],"deny":["Bash(git status:*)"]},"model":"opus"}' > "$ROOT/dotfiles/settings.json"
ln -s "$ROOT/dotfiles/settings.json" "$ROOT/settings.json"   # a dotfile-managed, symlinked settings file
export CLAUDE_USER_SETTINGS="$ROOT/settings.json"
# Stub ledger: numbers items D1, D2, ... unless PW_FAIL is set.
cat > "$ROOT/pending-watch.sh" <<'EOF'
[ -z "${PW_FAIL:-}" ] || { echo "pending-watch: boom" >&2; exit 1; }
n=$(( $(cat "$PW_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$PW_N"; cp "$4" "$PW_ITEMS.$n"; echo "D$n"
EOF
export PENDING_WATCH="$ROOT/pending-watch.sh" PW_N="$ROOT/pw.n" PW_ITEMS="$ROOT/item"
P="$ROOT/proj"; mkdir -p "$P/scripts"; touch "$P/scripts/build.sh" "$P/run.sh"
D="$ROOT/sup"; mkdir -p "$D"

pass=0; total=0
check() { total=$((total + 1)); if [ "$2" -eq 0 ]; then pass=$((pass + 1)); echo "ok   - $1"; else echo "FAIL - $1"; [ -z "${3:-}" ] || printf '       %s\n' "$3"; fi; }

hook() { # hook <pane> <tool> [command] ; cwd is the test project
  jq -nc --arg t "$2" --arg c "${3:-}" --arg cwd "$P" \
    '{session_id:"s1",cwd:$cwd,hook_event_name:"PermissionRequest",tool_name:$t,tool_input:(if $c=="" then {} else {command:$c} end)}' |
    HERDR_PANE_ID="$1" "${PS[@]}" log
}
times() { local n="$1"; shift; for _ in $(seq "$n"); do hook "$@"; done; }

# --- log
out="$(hook W:p1 Bash 'herdr tab get W:t1')"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ]; check "log prints nothing and exits 0" $? "rc=$rc out=$out"
jq -e '.pane=="W:p1" and .tool=="Bash" and .command=="herdr tab get W:t1"' "$PERMISSION_LOG" >/dev/null
check "log writes one line with pane, tool and command" $?
[ "$(stat -f %Lp "$PERMISSION_LOG" 2>/dev/null || stat -c %a "$PERMISSION_LOG")" = 600 ]; check "log file is private (600)" $?
out="$(printf 'not json' | "${PS[@]}" log)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ]; check "log ignores bad input and still exits 0" $?

# --- suggest below the threshold, and log lines that are not entries
times 1 W:p2 Bash 'herdr tab get W:t2'
printf '[]\n{"ts":"soon","tool":"Bash","command":"ls"}\n"x"\n' >> "$PERMISSION_LOG"
out="$("${PS[@]}" suggest "$D" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ]; check "suggest is silent below the threshold and skips non-entry lines" $? "rc=$rc $out"
jq -e '.since' "$D/permission-suggestions.json" >/dev/null; check "first suggest stores the start time" $?

# --- build the log: shapes that must be proposed
times 2 W:p2 Bash 'herdr tab get W:t3 2>/dev/null'
times 3 W:p3 Bash 'bash scripts/build.sh --fast'            # relative -> resolved against cwd
times 3 W:p3 Bash './run.sh'
times 3 W:p3 Bash 'cd /p && npm test -- --watch=false'      # compound, cd ignored
times 3 W:p3 Bash 'git status --short'                    # denied in user settings
times 3 W:p3 Bash 'ls -la build'
times 3 W:p3 mcp__linear__list_issues
# shapes that must not be proposed
not=(
  'rm -rf build' 'curl https://example.com' 'herdr pane run W:p1 ls' 'herdr agent prompt W:p1 hi'
  'cat .env' 'git -C /p status' 'herdr agent get W:p1' "/tmp/x/run.sh" 'ls > out.txt' 'echo $(whoami)'
  '/bin/rm -rf x' '/usr/bin/curl https://x' '/usr/bin/python3 -c "print(1)"' 'python3 -c "print(1)"'
  'timeout 5 curl x' 'nohup curl x' 'python3.11 -c 1' 'php -r 1' 'fish -c 1' 'uv run x.py'
  'pnpm dlx cowsay' 'docker compose run app sh' 'gh gist create f' 'aws s3 cp a s3://b'
  'aws ec2 terminate-instances --instance-ids i-1' 'kubectl scale deployment web --replicas=0'
  'git checkout -- .' 'git stash drop' 'git branch -D main' 'bash missing.sh' 'git -C /p log'
)
for c in "${not[@]}"; do times 3 W:p3 Bash "$c"; done
for t in mcp__claude-in-chrome__javascript_tool mcp__claude-in-chrome__computer mcp__db__execute_sql mcp__linear__archive_issue mcp__linear__delete_issue Edit; do
  times 3 W:p3 "$t"
done

out="$("${PS[@]}" suggest "$D")"; rc=$?
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = D1 ]; check "suggest adds one ledger item and prints its D<n> first" $? "$out"
has() { printf '%s\n' "$out" | grep -qF -- "$1"; }
has '(global): Bash(herdr tab get:*) — 4 lần, pane W:p1, W:p2'; check "read-only herdr rule, counted across panes" $? "$out"
has "(project): Bash(bash $P/scripts/build.sh:*)"; check "relative script under an interpreter becomes an absolute path" $? "$out"
has "(project): Bash($P/run.sh:*)"; check "relative ./script becomes an absolute path" $? "$out"
has '(global): Bash(npm test:*)'; check "compound command is split and cd ignored" $? "$out"
! has 'git status'; check "a rule the operator denied is not proposed" $? "$out"
has '(global): Bash(ls:*)'; check "read-only single command is proposed" $? "$out"
has '(global): mcp__linear__list_issues'; check "read-only MCP tool is proposed" $? "$out"
n="$(printf '%s\n' "$out" | sed 1d | wc -l | tr -d ' ')"
[ "$n" = 6 ]; check "nothing else is proposed (the unsafe shapes above are all dropped)" $? "got $n: $out"
! has 'Bash(./' && ! has 'Bash(bash scripts/'; check "no relative path rule" $? "$out"
item="$PW_ITEMS.1"
[ "$(sed -n 1p "$item")" = permissions ] && grep -q '^Câu hỏi:' "$item" && grep -q '^Chặn:' "$item"
check "ledger item has the scope line, question and Chặn:" $?
out2="$("${PS[@]}" suggest "$D")"
[ -z "$out2" ]; check "a second suggest is silent: proposed rules are not repeated" $? "$out2"

# --- a failed ledger add marks nothing
times 3 W:p4 Bash 'herdr pane list'
out="$(PW_FAIL=1 "${PS[@]}" suggest "$D" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ! jq -e '.rules["Bash(herdr pane list:*)"]' "$D/permission-suggestions.json" >/dev/null
check "when pending-watch add fails, suggest fails and marks nothing" $? "rc=$rc $out"
out="$("${PS[@]}" suggest "$D")"
[ "$(printf '%s\n' "$out" | head -1)" = D2 ] && printf '%s\n' "$out" | grep -qF 'P7 (global): Bash(herdr pane list:*)'
check "the next suggest proposes it again with the same P number" $? "$out"

# --- apply / decline
id_of() { jq -r --arg r "$1" '.rules[$r].id' "$D/permission-suggestions.json"; }
G="$(id_of 'Bash(herdr tab get:*)')"; PR="$(id_of "Bash(bash $P/scripts/build.sh:*)")"
"${PS[@]}" apply "$D" "$G" "$PR" >/dev/null; rc=$?
[ "$rc" -eq 0 ] && jq -e '(.permissions.allow | index("Bash(herdr tab get:*)")) and .model=="opus"' "$CLAUDE_USER_SETTINGS" >/dev/null
check "apply writes a global rule to user settings and keeps other keys" $?
[ -L "$CLAUDE_USER_SETTINGS" ]; check "a symlinked settings file stays a symlink" $?
jq -e --arg r "Bash(bash $P/scripts/build.sh:*)" 'index($r)' "$PROJECT_ALLOW_FILE" >/dev/null
check "apply writes a project rule to the project allow list" $?
"${PS[@]}" apply "$D" "$G" >/dev/null 2>&1; [ $? -ne 0 ]; check "apply refuses a rule that is no longer proposed" $?
"${PS[@]}" decline "$D" D1 >/dev/null
[ "$(jq '[.rules[] | select(.item=="D1" and .status=="proposed")] | length' "$D/permission-suggestions.json")" = 0 ] &&
  [ "$(jq -r '.rules["Bash(herdr pane list:*)"].status' "$D/permission-suggestions.json")" = proposed ]
check "decline D<n> declines the rest of that item only" $?
for _ in 1 2 3 4; do "${PS[@]}" apply "$D" all >/dev/null 2>&1; sleep 1; jq '.rules["Bash(herdr pane list:*)"].status="proposed"' "$D/permission-suggestions.json" > "$ROOT/s" && mv "$ROOT/s" "$D/permission-suggestions.json"; done
n="$(ls "$ROOT/dotfiles/settings.json".bak-permission-suggest-* | wc -l | tr -d ' ')"
[ "$n" = 3 ]; check "apply keeps only the newest three backups" $? "got $n"

times 5 W:p4 Bash 'npm test'
out="$("${PS[@]}" suggest "$D")"
[ -z "$out" ]; check "declined and applied rules are not proposed again" $? "$out"
out="$("${PS[@]}" suggest "$D" --since "$(( $(date +%s) + 60 ))")"
[ -z "$out" ]; check "--since drops older entries" $? "$out"

# --- seed
G2="$ROOT/repo"; mkdir -p "$G2"; git -C "$G2" init -q
echo '{"permissions":{"allow":["Bash(make test:*)"]}}' > "$ROOT/la.json"; mkdir -p "$G2/.claude"; cp "$ROOT/la.json" "$G2/.claude/settings.local.json"
printf '{}' | CLAUDE_PROJECT_DIR="$G2" "${PS[@]}" seed; rc=$?
[ "$rc" -eq 0 ] && jq -e --arg r "Bash(bash $P/scripts/build.sh:*)" '(.permissions.allow | index($r)) and (.permissions.allow | index("Bash(make test:*)"))' "$G2/.claude/settings.local.json" >/dev/null
check "seed merges project rules into the project's local settings and keeps its own" $?
before="$(cat "$G2/.claude/settings.local.json")"; printf '{}' | CLAUDE_PROJECT_DIR="$G2" "${PS[@]}" seed
[ "$before" = "$(cat "$G2/.claude/settings.local.json")" ]; check "seed is idempotent" $?
mkdir -p "$G2/sub"; printf '{}' | CLAUDE_PROJECT_DIR="$G2/sub" "${PS[@]}" seed
[ ! -e "$G2/sub/.claude" ]; check "seed skips a directory that is not a git root" $?

echo "$pass/$total passed"
[ "$pass" -eq "$total" ]
