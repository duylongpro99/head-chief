---
phase: 5
title: Live trial under Herdr
status: completed
effort: 1h
depends_on: [2, 3]
---

# Phase 5: Live trial under Herdr

## Context

The unit tests stub `herdr` and do not involve the Claude Code harness. Two facts can only be
checked live:
- whether the exit of a `run_in_background` command wakes an idle supervisor, and does so
  while an `AskUserQuestion` dialog is open;
- whether the real tab rename and notification look right.

## Requirements

Run in a scratch git repo, not in a consumer repo. Use the worktree's skill through
`./install.sh --project --skill roadmap-supervisor`, run from the worktree with the scratch
repo as the current directory. The scratch repo needs `.claude/` in its `.gitignore`
first, or `--project` refuses. The link resolves to the worktree, so the primary checkout's
consumers are unaffected.

1. Start a Claude Code supervisor session in Herdr on the scratch repo. Give it a two-item
   toy plan where each item is a trivial docs edit, so the supervisor opens two workers.
2. When the first worker is running, have the supervisor raise a decision `D1`. Confirm all three:
   the file has the item, the tab shows `⏳1`, and a notification appears.
3. Leave the dialog open until a worker report arrives. Record whether the dialog closed and whether `D1` stayed OPEN.
4. Edit `Answer:` for `D1` in the file with the dialog closed and the session idle. Measure the
   time until the supervisor records it as ANSWERED (target under 30 s).
5. Repeat step 4 with an `AskUserQuestion` dialog open for a second decision `D2`. Record
   whether the watcher exit woke the session.
6. Mark `D2` with chat `D2 seen`. Confirm the tab goes back to the base label and `line` prints nothing.
7. End the trial: the supervisor stops the workers and the watcher, and `pgrep -f pending-watch` is empty. Remove the scratch repo link.

## Files

- Add: `plans/261117-1152-roadmap-supervisor-pending-ledger/reports/phase-05-live-trial.md` with each step's observed result and timings.

## Validation

All seven steps are recorded with PASS or FAIL and evidence (screenshot path, `pane read` excerpt, timings).

## Stop condition

If step 5 shows that the exit does not wake the session while a dialog is open, stop and ask the operator. Options to present:
- (a) accept it: the answer is picked up when the dialog closes;
- (b) never open `AskUserQuestion` while workers run, and ask in text plus the ledger only;
- (c) other.

Do not change the design on your own.

## Risk and rollback

The trial spends real model turns, about five sessions for a few minutes. Nothing is committed except the report.
