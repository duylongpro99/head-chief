---
phase: 1
title: Register roadmap-supervisor in the repo
status: completed
effort: 0.5h
depends_on: []
---

# Phase 1: Register roadmap-supervisor in the repo

## Context

`git status` on `main` (95313bc) shows `?? skills/roadmap-supervisor/` and
`?? skills/head-chief/.env.mcp`. atoria already uses the untracked skill through a symlink.
README's skill table and the `skills.sh.json` grouping list only head-chief,
managed-session, pr-review-loop and envoy-peer.

## Requirements

- Create the worktree first. Every later phase works inside it:
  `git worktree add ../head-chief-pending-ledger -b feat/roadmap-supervisor-pending-ledger main`.
- Copy the untracked `skills/roadmap-supervisor/` from the primary checkout into the worktree,
  because untracked files do not follow `worktree add`. Use `cp -R`, then diff the two folders
  to confirm they are identical.
- Commit the skill exactly as it is now, before any change. This keeps the later diff reviewable.
- Add a `roadmap-supervisor` row to the README skill table, and fix the "ships four skills"
  sentence so its count matches the table.
- Add `roadmap-supervisor` to the "Session Orchestration" group in `skills.sh.json`.

## Files

- Add: `skills/roadmap-supervisor/**` (existing content)
- Modify: `README.md`, `skills.sh.json`
- Never stage: `skills/head-chief/.env.mcp`

## Steps

1. Create the worktree and copy the skill folder.
2. Run `git add skills/roadmap-supervisor` and commit `feat(roadmap-supervisor): add skill for supervising a roadmap or plan through worker sessions`.
3. Edit the README row and count, and `skills.sh.json`, then commit `docs: list roadmap-supervisor in README and skills.sh grouping`.

## Validation

- `git -C ../head-chief-pending-ledger ls-files skills/roadmap-supervisor | wc -l` reports 4.
- `diff -r ~/personal/head-chief/skills/roadmap-supervisor ../head-chief-pending-ledger/skills/roadmap-supervisor` prints nothing.
- `python3 -m json.tool skills.sh.json` succeeds.
- `git log --stat -2` shows no `.env.mcp`.

## Risk and rollback

There is low risk. The primary checkout is untouched. Rollback: `git worktree remove` and `git branch -D`.
