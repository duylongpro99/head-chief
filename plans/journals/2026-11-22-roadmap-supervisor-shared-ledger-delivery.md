---
title: "roadmap-supervisor shared ledger folder: delivery"
date: 2026-11-22
summary: "Shipped answers/record/archive, the shared ~/supervisor ledger and install grants in PR #8, after a review that found two answer-loss paths"
---

# roadmap-supervisor shared ledger folder: delivery

## What happened

The plan `plans/261122-0437-roadmap-supervisor-shared-ledger/` was delivered in the worktree
`head-chief-wt-shared-ledger` and merged as PR #8 (merge commit 52d9e12). It has one commit for
each of phases 1–4, plus one commit of review fixes. The rollout granted `~/supervisor` to atoria,
translate-side and tft-statistic, and a second `--sync-settings` run changed nothing.

## What the review caught

The code review found real data-loss paths that the phase tests had missed:

- `record` dropped the answer when the item had no `Answer:` line at all. The awk printed the
  answer only when it reached that line.
- Restarting a supervisor after `close` started an empty ledger. The final ledger's OPEN items
  were ignored, and later numbers could collide with the archive.
- Two supervisor folders using the same `--session` name in one project mapped to the same shared
  file.
- A stale archive copy of an item could silently win over a different live answer.

Each fix came with a test, and the suite grew from 30 to 35 tests. Lesson: when an item moves
between files, the test matrix needs the "item missing a line" case and the "item already
exists on the other side" case, not only the happy move.

## Live trial

Two real Sonnet supervisors under Herdr ran the whole loop. The main findings:

- A running Claude Code session picks up a new `permissions.additionalDirectories` entry with no
  restart.
- The sandbox needs no extra entry.
- Supervisors used `answers` instead of reading the ledger.

Details are in `reports/live-trial.md`. One mistake on my side: the first stub-notifier check hung
because `add` reads its item from stdin.

## Left as accepted

- A symlinked `settings.local.json` is replaced by a regular file.
- The test-only swap hook stays in the script.
- Revoking the last grant leaves `{}` in `settings.local.json` instead of deleting the file.
