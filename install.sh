#!/usr/bin/env bash
# install.sh — symlink skills from this checkout into a host's skill folder (development and testing).
#
#   ./install.sh [--skill NAME ...] [--target DIR | --project | --agents] [--uninstall] [--force] [--dry-run]
#   ./install.sh --sync-settings [--scan DIR ...] [--force] [--dry-run]
#
#   --skill NAME   skill under skills/ to link (repeatable; default: envoy-peer). Skills named
#                  in its SKILL.md frontmatter `metadata.requires` are linked too (one level);
#                  a dependency already present in any form is left as is, even with --force
#   --target DIR   link into DIR (default: ~/.claude/skills)
#   --agents       link into ~/.agents/skills
#   --project      link into <git root of $PWD>/.claude/skills (the current folder when it has no git);
#                  refused unless git ignores the link (--force overrides)
#   --uninstall    remove links that point into this checkout; anything else is left alone.
#                  Only the named skills: dependencies are never removed
#   --force        replace an existing symlink that points elsewhere (never a real file or folder);
#                  also grants access in a repo where git does not ignore settings.local.json
#   --dry-run      print the actions without doing them
#   --sync-settings  grant the supervisor folder to every repo in $SUPERVISOR_HOME/.installs;
#                  a repo that no longer exists is warned about and kept in the list
#   --scan DIR     with --sync-settings: first add every repo under DIR (6 levels deep) whose
#                  .claude/skills/roadmap-supervisor links into this checkout (repeatable)
#
# roadmap-supervisor with --project also creates $SUPERVISOR_HOME (default ~/supervisor), adds
# it to <repo>/.claude/settings.local.json permissions.additionalDirectories (needs jq; the old
# file is kept as settings.local.json.bak when it changes) and records the repo in
# $SUPERVISOR_HOME/.installs. --uninstall --project removes that entry and that line only;
# the folder itself is never deleted. User-scope settings are never written.
#
# The links follow this checkout's current HEAD: switching branches here changes the
# skill for every project that uses the link. Distribution still goes through
# `npx skills add`, which copies instead of linking.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
die() { echo "install.sh: $*" >&2; exit 1; }
usage() { sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; }

skills=(); target=""; where=""; uninstall=0; force=0; dry=0; sync=0; scan_dirs=()
set_where() { [ -z "$where" ] || die "--target, --project and --agents are mutually exclusive"; where="$1"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skill) [ "$#" -ge 2 ] || die "--skill needs a name"; skills+=("$2"); shift 2 ;;
    --target) [ "$#" -ge 2 ] || die "--target needs a folder"; set_where target; target="$2"; shift 2 ;;
    --project) set_where project; shift ;;
    --agents) set_where agents; shift ;;
    --uninstall) uninstall=1; shift ;;
    --force) force=1; shift ;;
    --dry-run) dry=1; shift ;;
    --sync-settings) sync=1; shift ;;
    --scan) [ "$#" -ge 2 ] || die "--scan needs a folder"; [ -d "$2" ] || die "--scan: no folder $2"; scan_dirs+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
if [ "$sync" = 1 ]; then
  [ "${#skills[@]}" = 0 ] && [ -z "$where" ] && [ "$uninstall" = 0 ] \
    || die "--sync-settings takes only --scan, --force and --dry-run"
elif [ "${#scan_dirs[@]}" -gt 0 ]; then
  die "--scan needs --sync-settings"
fi
[ "${#skills[@]}" -gt 0 ] || skills=(envoy-peer)

SUPERVISOR_SKILL=roadmap-supervisor
SUP="${SUPERVISOR_HOME:-$HOME/supervisor}"
SUP="${SUP%/}"
case "$SUP" in /?*) ;; *) die "SUPERVISOR_HOME must be an absolute path (got '$SUP')" ;; esac
REGISTRY="$SUP/.installs"

# In --dry-run nothing changes on disk and every action line is prefixed "[dry-run]".
run() { [ "$dry" = 1 ] || "$@"; }
say() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else echo "$*"; fi; }

# would_commit <root> <path>: true when <root> is a git work tree that does not ignore <path>.
# A folder with no git has nothing to commit, so a link or settings file there is safe.
would_commit() {
  git -C "$1" rev-parse --is-inside-work-tree > /dev/null 2>&1 || return 1
  ! git -C "$1" check-ignore -q "$2"
}

# The settings fragment a user without jq merges by hand.
paste_json() {
  local d="${SUP//\\/\\\\}"; d="${d//\"/\\\"}"
  printf '{"permissions":{"additionalDirectories":["%s"]}}\n' "$d"
}

# Repos registered as having roadmap-supervisor, one absolute path per line.
registry_add() {
  if [ -f "$REGISTRY" ] && grep -qxF -- "$1" "$REGISTRY"; then return 0; fi
  if [ "$dry" = 0 ]; then printf '%s\n' "$1" >> "$REGISTRY"; fi
  say "registered $1 in $REGISTRY"
}
registry_remove() {
  [ -f "$REGISTRY" ] && grep -qxF -- "$1" "$REGISTRY" || return 0
  if [ "$dry" = 0 ]; then
    local tmp; tmp="$(mktemp "$REGISTRY.XXXXXX")"
    grep -vxF -- "$1" "$REGISTRY" > "$tmp" || true
    mv "$tmp" "$REGISTRY"
  fi
  say "unregistered $1 from $REGISTRY"
}

# write_settings <file> <jq filter>: apply the filter through a temp file, keeping the old
# content in <file>.bak. Callers only call it when the content will change.
write_settings() {
  local file="$1" filter="$2" tmp
  [ "$dry" = 1 ] && return 0
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp "$file.XXXXXX")"
  if [ -f "$file" ]; then
    jq --arg d "$SUP" "$filter" "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
    cp -p "$file" "$file.bak"
    # mktemp makes the file 0600; keep the mode the settings file already had.
    # GNU stat first: GNU `stat -f` prints file-system data and fails, BSD `stat -c` only fails.
    chmod "$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file")" "$tmp"
  else
    jq --arg d "$SUP" "$filter" <<< '{}' > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp"
  fi
  mv "$tmp" "$file"
}

# settings_shape_ok <file>: a JSON object whose permissions (if any) is an object and whose
# additionalDirectories (if any) is an array, so the jq filters below cannot misfire.
settings_shape_ok() {
  jq -e 'type == "object"
         and ((.permissions // {}) | type == "object")
         and (((.permissions // {}).additionalDirectories // []) | type == "array")' "$1" > /dev/null 2>&1
}

# grant_supervisor_dir <root>: let Claude sessions in <root> use $SUP. Sandboxed Bash needs
# nothing more: additionalDirectories also grants sandbox writes.
grant_supervisor_dir() {
  local root="$1" file="$1/.claude/settings.local.json"
  if would_commit "$root" "$file"; then
    if [ "$force" = 1 ]; then
      echo "warning: $file is not ignored by git; granting anyway (--force)" >&2
    else
      echo "error: $file is not ignored by git and would be committed; add .claude/settings.local.json (or .claude) to $root/.gitignore, or pass --force" >&2
      return 1
    fi
  fi
  [ -d "$SUP" ] || { run mkdir -p "$SUP"; say "created $SUP"; }
  registry_add "$root"
  if ! command -v jq > /dev/null 2>&1; then
    echo "error: jq is not installed, so $file was not changed. Install jq and rerun, or merge this into it by hand:" >&2
    paste_json
    return 1
  fi
  if [ -f "$file" ]; then
    settings_shape_ok "$file" || { echo "error: $file is not a JSON object with permissions.additionalDirectories as a list; fix it by hand" >&2; return 1; }
    if jq -e --arg d "$SUP" '(.permissions.additionalDirectories // []) | index($d) != null' "$file" > /dev/null; then
      echo "already granted: $SUP in $file"; return 0
    fi
  fi
  # shellcheck disable=SC2016  # $d is a jq variable
  write_settings "$file" '.permissions = ((.permissions // {}) | .additionalDirectories = ((.additionalDirectories // []) + [$d]))' || return 1
  say "granted $SUP in $file"
}

# revoke_supervisor_dir <root>: undo the grant. The additionalDirectories key goes when its
# list empties, and permissions goes when that left it empty. $SUP itself is never deleted.
revoke_supervisor_dir() {
  local root="$1" file="$1/.claude/settings.local.json"
  if [ -f "$file" ]; then
    if ! command -v jq > /dev/null 2>&1; then
      echo "error: jq is not installed; remove \"$SUP\" from permissions.additionalDirectories in $file by hand" >&2
      return 1
    fi
    settings_shape_ok "$file" || { echo "error: $file is not a JSON object with permissions.additionalDirectories as a list; fix it by hand" >&2; return 1; }
    if jq -e --arg d "$SUP" '(.permissions.additionalDirectories // []) | index($d) != null' "$file" > /dev/null; then
      # shellcheck disable=SC2016  # $d is a jq variable
      write_settings "$file" '.permissions.additionalDirectories -= [$d]
        | if .permissions.additionalDirectories == [] then del(.permissions.additionalDirectories) else . end
        | if .permissions == {} then del(.permissions) else . end' || return 1
      say "revoked $SUP in $file"
    fi
  fi
  registry_remove "$root"
}

if [ "$sync" = 1 ]; then
  roots=()
  add_root() { local r; for r in ${roots[@]+"${roots[@]}"}; do [ "$r" = "$1" ] && return 0; done; roots+=("$1"); }
  if [ -f "$REGISTRY" ]; then
    while IFS= read -r line || [ -n "$line" ]; do [ -z "$line" ] || add_root "$line"; done < "$REGISTRY"
  fi
  want="$(cd -P "$REPO/skills/$SUPERVISOR_SKILL" && pwd -P)" || die "no skill $SUPERVISOR_SKILL in $REPO/skills"
  for dir in ${scan_dirs[@]+"${scan_dirs[@]}"}; do
    while IFS= read -r link; do
      [ "$(cd -P "$link" 2>/dev/null && pwd -P)" = "$want" ] || continue
      # The git root, or the folder holding .claude when it is not in a git repository.
      base="${link%/.claude/skills/"$SUPERVISOR_SKILL"}"
      root="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null)" || root="$(cd -P "$base" && pwd -P)"
      echo "found $link"; add_root "$root"
    done < <(find "$dir" -maxdepth 6 \( -name node_modules -o -name .git \) -prune \
               -o -type l -path "*/.claude/skills/$SUPERVISOR_SKILL" -print 2>/dev/null)
  done
  [ "${#roots[@]}" -gt 0 ] || { echo "no repos registered in $REGISTRY; pass --scan DIR to find them"; exit 0; }
  failed=0
  for root in "${roots[@]}"; do
    if [ ! -d "$root" ]; then echo "warning: $root no longer exists; skipped (still listed in $REGISTRY)" >&2; continue; fi
    grant_supervisor_dir "$root" || failed=1
  done
  exit "$failed"
fi

project_root=""
case "$where" in
  ""|global) target="$HOME/.claude/skills" ;;
  agents) target="$HOME/.agents/skills" ;;
  project)
    # The git root, or the current folder when it is not in a git repository.
    project_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || project_root="$(pwd -P)"
    target="$project_root/.claude/skills" ;;
  target) ;;
esac

# Names listed under `requires:` in a skill's frontmatter, space- or comma-separated.
requires_of() {
  awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
       NR > 1 && /^[[:space:]]*requires:/ { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/[,"\047]/, " "); print }' "$1"
}

# Link each skill's dependencies too, right after it, once. Uninstall never expands.
deps_only=()
is_dep_only() { local e; for e in ${deps_only[@]+"${deps_only[@]}"}; do [ "$e" = "$1" ] && return 0; done; return 1; }
if [ "$uninstall" = 0 ]; then
  expanded=()
  has() { local e; for e in ${expanded[@]+"${expanded[@]}"}; do [ "$e" = "$1" ] && return 0; done; return 1; }
  requested() { local e; for e in "${skills[@]}"; do [ "$e" = "$1" ] && return 0; done; return 1; }
  for name in "${skills[@]}"; do
    has "$name" || expanded+=("$name")
    [ -f "$REPO/skills/$name/SKILL.md" ] || continue
    for dep in $(requires_of "$REPO/skills/$name/SKILL.md"); do
      [ -f "$REPO/skills/$dep/SKILL.md" ] || die "skill '$name' requires '$dep', which is not in $REPO/skills"
      has "$dep" && continue
      requested "$dep" || { say "adding dependency $dep (required by $name)"; deps_only+=("$dep"); }
      expanded+=("$dep")
    done
  done
  skills=("${expanded[@]}")
fi

failed=0; supervisor_present=0
for name in "${skills[@]}"; do
  src="$REPO/skills/$name"
  link="$target/$name"
  present() { [ "$name" != "$SUPERVISOR_SKILL" ] || supervisor_present=1; }
  if [ "$uninstall" = 1 ]; then
    still_installed=0
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
      run rm "$link"; say "removed $link"
    elif [ -L "$link" ]; then
      echo "skipped $link (points to $(readlink "$link"), not this checkout)"; still_installed=1
    elif [ -e "$link" ]; then
      echo "skipped $link (not a symlink)"; still_installed=1
    else
      echo "not installed: $link"
    fi
    if [ -n "$project_root" ] && [ "$name" = "$SUPERVISOR_SKILL" ]; then
      if [ "$still_installed" = 1 ]; then
        echo "kept the $SUP grant: $SUPERVISOR_SKILL is still installed at $link"
      else
        revoke_supervisor_dir "$project_root" || failed=1
      fi
    fi
    continue
  fi
  if [ ! -f "$src/SKILL.md" ]; then echo "error: no skill '$name' in $REPO/skills" >&2; failed=1; continue; fi
  # A dependency nobody named is satisfied by whatever is already there.
  if is_dep_only "$name" && { [ -L "$link" ] || [ -e "$link" ]; }; then
    if [ -L "$link" ]; then echo "dependency present: $link -> $(readlink "$link")"; else echo "dependency present: $link"; fi
    present; continue
  fi

  if [ -n "$project_root" ] && would_commit "$project_root" "$link"; then
    if [ "$force" = 1 ]; then
      echo "warning: $link is not ignored by git; linking anyway (--force)" >&2
    else
      echo "error: $link is not ignored by git and would be committed; add .claude/skills/ (or .claude) to $project_root/.gitignore, or pass --force" >&2
      failed=1; continue
    fi
  fi

  if [ -L "$link" ]; then
    cur="$(readlink "$link")"
    if [ "$cur" = "$src" ]; then echo "already linked: $link -> $src"; present; continue; fi
    if [ "$force" = 1 ]; then
      run rm "$link"; run ln -s "$src" "$link"; say "relinked $link -> $src (was $cur)"; present
    else
      echo "error: $link already links to $cur; pass --force to replace it" >&2; failed=1
    fi
  elif [ -e "$link" ]; then
    echo "error: $link exists and is not a symlink; remove it by hand (--force only replaces symlinks)" >&2; failed=1
  else
    [ -d "$target" ] || run mkdir -p "$target"
    run ln -s "$src" "$link"; say "linked $link -> $src"; present
  fi
done

if [ "$supervisor_present" = 1 ]; then
  if [ -n "$project_root" ]; then
    grant_supervisor_dir "$project_root" || failed=1
  else
    echo "note: $SUPERVISOR_SKILL needs access to $SUP, which is granted per repo: rerun with --project inside each repo, or use --sync-settings"
  fi
fi
exit "$failed"
