#!/usr/bin/env bash
# install.sh — symlink skills from this checkout into a host's skill folder (development and testing).
#
#   ./install.sh [--skill NAME ...] [--target DIR | --project | --agents] [--uninstall] [--force] [--dry-run]
#
#   --skill NAME   skill under skills/ to link (repeatable; default: envoy-peer)
#   --target DIR   link into DIR (default: ~/.claude/skills)
#   --agents       link into ~/.agents/skills
#   --project      link into <git root of $PWD>/.claude/skills; refused unless git ignores the link (--force overrides)
#   --uninstall    remove links that point into this checkout; anything else is left alone
#   --force        replace an existing symlink that points elsewhere (never a real file or folder)
#   --dry-run      print the actions without doing them
#
# The links follow this checkout's current HEAD: switching branches here changes the
# skill for every project that uses the link. Distribution still goes through
# `npx skills add`, which copies instead of linking.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
die() { echo "install.sh: $*" >&2; exit 1; }
usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

skills=(); target=""; where=""; uninstall=0; force=0; dry=0
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
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ "${#skills[@]}" -gt 0 ] || skills=(envoy-peer)

project_root=""
case "$where" in
  ""|global) target="$HOME/.claude/skills" ;;
  agents) target="$HOME/.agents/skills" ;;
  project)
    project_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || die "--project needs a git repository (cwd: $PWD)"
    target="$project_root/.claude/skills" ;;
  target) ;;
esac

# In --dry-run nothing changes on disk and every action line is prefixed "[dry-run]".
run() { [ "$dry" = 1 ] || "$@"; }
say() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else echo "$*"; fi; }

failed=0
for name in "${skills[@]}"; do
  src="$REPO/skills/$name"
  link="$target/$name"
  if [ "$uninstall" = 1 ]; then
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
      run rm "$link"; say "removed $link"
    elif [ -L "$link" ]; then
      echo "skipped $link (points to $(readlink "$link"), not this checkout)"
    elif [ -e "$link" ]; then
      echo "skipped $link (not a symlink)"
    else
      echo "not installed: $link"
    fi
    continue
  fi
  if [ ! -f "$src/SKILL.md" ]; then echo "error: no skill '$name' in $REPO/skills" >&2; failed=1; continue; fi

  if [ -n "$project_root" ] && ! git -C "$project_root" check-ignore -q "$link"; then
    if [ "$force" = 1 ]; then
      echo "warning: $link is not ignored by git; linking anyway (--force)" >&2
    else
      echo "error: $link is not ignored by git and would be committed; add .claude/skills/ (or .claude) to $project_root/.gitignore, or pass --force" >&2
      failed=1; continue
    fi
  fi

  if [ -L "$link" ]; then
    cur="$(readlink "$link")"
    if [ "$cur" = "$src" ]; then echo "already linked: $link -> $src"; continue; fi
    if [ "$force" = 1 ]; then
      run rm "$link"; run ln -s "$src" "$link"; say "relinked $link -> $src (was $cur)"
    else
      echo "error: $link already links to $cur; pass --force to replace it" >&2; failed=1
    fi
  elif [ -e "$link" ]; then
    echo "error: $link exists and is not a symlink; remove it by hand (--force only replaces symlinks)" >&2; failed=1
  else
    [ -d "$target" ] || run mkdir -p "$target"
    run ln -s "$src" "$link"; say "linked $link -> $src"
  fi
done
exit "$failed"
