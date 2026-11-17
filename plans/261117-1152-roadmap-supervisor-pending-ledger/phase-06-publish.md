---
phase: 6
title: "Publish: PR and merge (operator gate)"
status: completed
effort: 0.5h
depends_on: [4, 5]
---

# Phase 6: Publish (PR and merge, operator gate)

## Context

`npx skills` installs from GitHub's default branch (`duylongpro99/head-chief`). The symlink
consumers see the change only once the primary checkout at `~/personal/head-chief` is on a
`main` that contains it.

## Requirements

1. Ask the operator before `git push`. Show the commit list (`git log --oneline main..HEAD`)
   and the test result from phase 2.
2. Push the branch and open a PR with `gh pr create`. The body has the summary, the test output
   and a link to the phase-05 report. End it with the attribution line from the session reminder.
3. Ask the operator before merging. After approval, run `gh pr merge --merge`.
4. Run `git -C ~/personal/head-chief pull --ff-only` on `main`. Before pulling, confirm no
   supervisor is mid-run in atoria (`herdr pane list`, then ask the operator if one is).
5. Remove the worktree and delete the local branch.

## Validation

- `gh pr view --json state` reports `MERGED`.
- `git -C ~/personal/head-chief log --oneline -1` is the merge commit.
- `git -C ~/personal/head-chief status --short` still shows only `skills/head-chief/.env.mcp`
  as untracked. The previously untracked `skills/roadmap-supervisor/` copy is now tracked
  and identical; if `pull` refuses because of untracked files, move the untracked copy aside
  first and diff it after the pull.
- `git worktree list` no longer lists `head-chief-pending-ledger`.

## Risk and rollback

The pull is likely to conflict with the untracked `skills/roadmap-supervisor/` in the primary
checkout. Handle it as described above, and never delete the copy without diffing it.
Rollback: revert the merge commit on `main`.
