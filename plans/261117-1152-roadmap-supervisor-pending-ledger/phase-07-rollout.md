---
phase: 7
title: Roll out to atoria, translate-side, tft-statistic
status: completed
effort: 1h
depends_on: [6]
---

# Phase 7: Roll out to atoria, translate-side and tft-statistic

## Context (verified 2026-11-17)

| Repo | roadmap-supervisor | managed-session | Action |
|---|---|---|---|
| `~/personal/agent/atoria` | symlink → `~/personal/head-chief/skills/roadmap-supervisor` | symlink → head-chief | verify only |
| `~/personal/agent/translate-side` | absent | symlink → `general-cc-kit/skills/head-chief/skills/managed-session` (stale clone, 992308b) | relink managed-session, add roadmap-supervisor |
| `~/personal/tft-statistic` | absent | absent | add roadmap-supervisor (and managed-session through requires) |

`.claude/skills` is git-ignored in all three, so `--project` will not refuse.

## Requirements

1. Run the README's consumer-finding command and confirm that the table above is still accurate.
   If a repo outside these three shows up, list it in the report and do not touch it.
2. translate-side: from the repo root, run
   `~/personal/head-chief/install.sh --project --force --skill roadmap-supervisor --skill managed-session`.
   This adds roadmap-supervisor and relinks managed-session (a dependency is only relinked when named). `--force` replaces only symlinks.
   Leave `general-cc-kit/skills/head-chief` untouched.
3. tft-statistic: from the repo root, run `~/personal/head-chief/install.sh --project --skill roadmap-supervisor`.
4. atoria: run `~/personal/head-chief/install.sh --project --skill roadmap-supervisor`. Expect
   "already linked" for both skills.
5. In each repo, confirm the links resolve:
   `readlink .claude/skills/roadmap-supervisor .claude/skills/managed-session`, and
   `test -x .claude/skills/roadmap-supervisor/scripts/pending-watch.sh`.
6. In each repo, confirm `git status --short` shows nothing new, because the links are ignored.

## Files

The only changes are symlinks under each repo's `.claude/skills/`. No commit is made in any consumer repo.

## Validation

- Six `readlink` results all point into `/Users/onedayin20902/personal/head-chief/skills/`.
- `find ~/personal/agent/translate-side/.claude/skills -lname '*general-cc-kit*'` prints nothing.
- `git status --short` is unchanged in all three repos.

## Risk and rollback

Rollback for a repo: `~/personal/head-chief/install.sh --uninstall --project --skill roadmap-supervisor --skill managed-session`.
For translate-side, also restore the old link:
`ln -s ~/personal/agent/general-cc-kit/skills/head-chief/skills/managed-session .claude/skills/managed-session`.
