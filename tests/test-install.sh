#!/usr/bin/env bash
# Tests for install.sh granting the supervisor folder per repo. Runs in a temp HOME with temp
# git repos, so the real ~/supervisor, ~/.claude and consumer repos are never touched.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/.." && pwd -P)"
INSTALL="$REPO/install.sh"
ROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$ROOT"' EXIT

export HOME="$ROOT/home"
unset SUPERVISOR_HOME
SUP="$HOME/supervisor"
mkdir -p "$HOME"
case "$SUP" in "$ROOT"/*) ;; *) echo "refusing to run: supervisor folder $SUP is outside the temp dir"; exit 1 ;; esac

pass=0; total=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
fail() { echo "FAIL - $1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
check() { # check <name> <command...>
  local name="$1"; shift
  total=$((total + 1))
  if "$@"; then ok "$name"; else fail "$name" "${OUT:-}"; fi
}

# new_repo <path> [gitignore line]: a git repo that ignores .claude/ unless told otherwise.
new_repo() {
  mkdir -p "$1" && git -C "$1" init -q && printf '%s\n' "${2:-.claude/}" > "$1/.gitignore"
}
# in_repo <repo> <install args...>: run install.sh from the repo; output in $OUT, status in $RC.
in_repo() { local r="$1"; shift; OUT="$(cd "$r" && "$INSTALL" "$@" 2>&1)"; RC=$?; }
install_cmd() { OUT="$("$INSTALL" "$@" 2>&1)"; RC=$?; }
# snapshot: path and content hash (or link target) of every file under the temp dir, minus .git.
snapshot() {
  find "$ROOT" -name .git -prune -o \( -type f -o -type l -o -type d \) -print | LC_ALL=C sort |
    while IFS= read -r f; do
      if [ -L "$f" ]; then echo "L $f -> $(readlink "$f")"
      elif [ -d "$f" ]; then echo "D $f"
      else echo "F $f $(shasum < "$f" | cut -d' ' -f1)"; fi
    done
}
settings() { printf '%s/.claude/settings.local.json' "$1"; }
dirs_of() { jq -c '.permissions.additionalDirectories' "$(settings "$1")" 2>/dev/null; }
registered() { grep -qxF -- "$1" "$SUP/.installs" 2>/dev/null; }
unregistered() { ! registered "$1"; }

# Install into a repo with no settings file.
A="$ROOT/repos/alpha"; new_repo "$A"
in_repo "$A" --project --skill roadmap-supervisor
check "install exits 0" [ "$RC" = 0 ]
check "install creates the supervisor folder" [ -d "$SUP" ]
check "install adds the folder to additionalDirectories" [ "$(dirs_of "$A")" = "[\"$SUP\"]" ]
check "install records the repo in the registry" registered "$A"
check "install with no settings file leaves no .bak" [ ! -e "$(settings "$A").bak" ]
before="$(snapshot)"
in_repo "$A" --project --skill roadmap-supervisor
check "second install exits 0" [ "$RC" = 0 ]
check "second install changes nothing" [ "$before" = "$(snapshot)" ]
check "second install keeps one registry line" [ "$(grep -cxF -- "$A" "$SUP/.installs")" = 1 ]

# Existing keys survive, and the old content goes to .bak.
B="$ROOT/repos/beta"; new_repo "$B"; mkdir -p "$B/.claude"
old='{"model":"opus","permissions":{"allow":["Bash(ls)"],"additionalDirectories":["/opt/other"]}}'
printf '%s\n' "$old" > "$(settings "$B")"
chmod 640 "$(settings "$B")"
in_repo "$B" --project --skill roadmap-supervisor
check "install into existing settings exits 0" [ "$RC" = 0 ]
check "existing keys survive" [ "$(jq -c '[.model, .permissions.allow]' "$(settings "$B")")" = '["opus",["Bash(ls)"]]' ]
check "folder is appended after existing entries" [ "$(dirs_of "$B")" = "[\"/opt/other\",\"$SUP\"]" ]
check ".bak holds the old content" [ "$(cat "$(settings "$B").bak")" = "$old" ]
check "rewritten settings keep their file mode" [ "$(stat -f %Lp "$(settings "$B")")" = 640 ]
check "new settings are readable like a normal file" [ "$(stat -f %Lp "$(settings "$A")")" = 644 ]

# A repo where git would commit settings.local.json is refused without --force.
C="$ROOT/repos/gamma"; new_repo "$C" ".claude/skills/"
in_repo "$C" --project --skill roadmap-supervisor
check "unignored settings is refused" [ "$RC" != 0 ]
check "refusal names settings.local.json" grep -qF "settings.local.json is not ignored" <<< "$OUT"
check "refused repo gets no settings file" [ ! -e "$(settings "$C")" ]
check "refused repo is not registered" unregistered "$C"
in_repo "$C" --project --skill roadmap-supervisor --force
check "--force install exits 0 in an unignored repo" [ "$RC" = 0 ]
check "--force grants in an unignored repo" [ "$(dirs_of "$C")" = "[\"$SUP\"]" ]

# A global target only explains that access is per repo.
install_cmd --skill roadmap-supervisor --dry-run
check "global target prints the per-repo note" grep -qF "granted per repo" <<< "$OUT"

# --sync-settings --scan finds a pre-existing link, skips a link elsewhere and a missing repo,
# and still refuses the registered repo whose settings git would commit (it needs --force).
D="$ROOT/scan/work/delta"; new_repo "$D"; mkdir -p "$D/.claude/skills"
ln -s "$REPO/skills/roadmap-supervisor" "$D/.claude/skills/roadmap-supervisor"
E="$ROOT/scan/epsilon"; new_repo "$E"; mkdir -p "$E/.claude/skills" "$ROOT/elsewhere"
ln -s "$ROOT/elsewhere" "$E/.claude/skills/roadmap-supervisor"
printf '%s\n' "$ROOT/repos/gone" >> "$SUP/.installs"
install_cmd --sync-settings --scan "$ROOT/scan"
check "sync exits 1 because one repo is refused" [ "$RC" = 1 ]
check "sync names the refused repo" grep -qF "$C/.claude/settings.local.json is not ignored" <<< "$OUT"
check "sync grants the scanned repo" [ "$(dirs_of "$D")" = "[\"$SUP\"]" ]
check "sync registers the scanned repo" registered "$D"
check "sync ignores a link that points elsewhere" [ ! -e "$(settings "$E")" ]
check "sync warns about a missing repo" grep -qF "$ROOT/repos/gone no longer exists" <<< "$OUT"
check "sync keeps the missing repo in the registry" registered "$ROOT/repos/gone"
before="$(snapshot)"
install_cmd --sync-settings --scan "$ROOT/scan"
check "second sync gives the same status" [ "$RC" = 1 ]
check "second sync changes nothing" [ "$before" = "$(snapshot)" ]

# Uninstall removes only the entry and the registry line.
in_repo "$B" --uninstall --project --skill roadmap-supervisor
check "uninstall exits 0" [ "$RC" = 0 ]
check "uninstall keeps other entries and keys" \
  [ "$(jq -c . "$(settings "$B")")" = '{"model":"opus","permissions":{"allow":["Bash(ls)"],"additionalDirectories":["/opt/other"]}}' ]
check "uninstall removes the registry line" unregistered "$B"
check "uninstall keeps other registry lines" registered "$A"
check "uninstall keeps the supervisor folder" [ -d "$SUP" ]
check "uninstall removes the skill link" [ ! -L "$B/.claude/skills/roadmap-supervisor" ]
in_repo "$A" --uninstall --project --skill roadmap-supervisor
check "uninstall drops the keys it emptied" [ "$(jq -c . "$(settings "$A")")" = '{}' ]

# A link into another clone is not this checkout's to remove, so the grant stays too.
E="$ROOT/repos/elsewhere"; new_repo "$E"
in_repo "$E" --project --skill roadmap-supervisor
ln -sfn "$ROOT/other-clone/skills/roadmap-supervisor" "$E/.claude/skills/roadmap-supervisor"
in_repo "$E" --uninstall --project --skill roadmap-supervisor
check "uninstall keeps the grant while another clone's link is installed" [ "$(dirs_of "$E")" = "[\"$SUP\"]" ]
check "uninstall says why it kept the grant" grep -qF "kept the $SUP grant" <<< "$OUT"

# --dry-run changes nothing, for install, sync and uninstall.
F="$ROOT/repos/zeta"; new_repo "$F"
before="$(snapshot)"
OUT="$(cd "$F" && SUPERVISOR_HOME="$ROOT/sup-dry" "$INSTALL" --project --skill roadmap-supervisor --dry-run 2>&1)"; RC=$?
check "dry-run install exits 0" [ "$RC" = 0 ]
check "dry-run install prints the grant" grep -qF "[dry-run] granted $ROOT/sup-dry" <<< "$OUT"
install_cmd --sync-settings --scan "$ROOT/repos" --dry-run
in_repo "$C" --uninstall --project --skill roadmap-supervisor --dry-run
check "dry-run uninstall prints the revoke" grep -qF "[dry-run] revoked $SUP" <<< "$OUT"
check "dry-run changes nothing" [ "$before" = "$(snapshot)" ]

# Without jq: exit 1, print the JSON to paste, leave settings alone.
NOJQ="$ROOT/nojq-bin"; mkdir -p "$NOJQ"
for t in env bash git dirname sed awk grep mkdir ln rm readlink mktemp mv cp cat find; do
  ln -s "$(command -v "$t")" "$NOJQ/$t"
done
G="$ROOT/repos/eta"; new_repo "$G"
OUT="$(cd "$G" && PATH="$NOJQ" "$INSTALL" --project --skill roadmap-supervisor 2>&1)"; RC=$?
check "missing jq exits 1" [ "$RC" = 1 ]
check "missing jq prints the JSON to paste" grep -qxF "{\"permissions\":{\"additionalDirectories\":[\"$SUP\"]}}" <<< "$OUT"
check "missing jq leaves settings alone" [ ! -e "$(settings "$G")" ]

# A folder with no git still gets the skill: nothing there can be committed by accident.
N="$ROOT/plain/nogit"; mkdir -p "$N/sub"
in_repo "$N" --project --skill roadmap-supervisor
check "install in a folder with no git exits 0" [ "$RC" = 0 ]
check "install in a folder with no git links the skill there" [ -L "$N/.claude/skills/roadmap-supervisor" ]
check "install in a folder with no git grants the supervisor folder" [ "$(dirs_of "$N")" = "[\"$SUP\"]" ]
check "install in a folder with no git registers it" registered "$N"
in_repo "$N" --uninstall --project --skill roadmap-supervisor
check "uninstall in a folder with no git revokes and unregisters" sh -c '[ ! -L "$1/.claude/skills/roadmap-supervisor" ] && ! grep -qxF -- "$1" "$2/.installs"' _ "$N" "$SUP"

# --scan finds a link in a folder with no git and grants that folder.
P="$ROOT/scan-plain/proj"; mkdir -p "$P/.claude/skills"
ln -s "$REPO/skills/roadmap-supervisor" "$P/.claude/skills/roadmap-supervisor"
install_cmd --sync-settings --scan "$ROOT/scan-plain"
check "sync --scan reports the grant for a folder with no git" grep -qxF "granted $SUP in $P/.claude/settings.local.json" <<< "$OUT"
check "sync --scan does not skip a folder with no git" sh -c '! grep -q "not inside a git" <<EOF
$1
EOF' _ "$OUT"
check "sync --scan registers a folder with no git" registered "$P"
check "sync --scan grants a folder with no git" [ "$(dirs_of "$P")" = "[\"$SUP\"]" ]

echo "$pass/$total passed"
[ "$pass" = "$total" ]
