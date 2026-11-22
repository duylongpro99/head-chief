---
title: "Phase 6: Publish and roll out (operator gate)"
status: done
---

# Phase 6: Publish and roll out (operator gate)

## Overview

Priority P1, 1h. Merge one PR, then grant access in the existing consumer repos.

## Steps

1. One PR from branch `feat/roadmap-supervisor-shared-ledger` (one commit per phase). Before it:
   both test files green and a code review (`ak:code-review`).
2. Ask the operator before the `git push` and before the merge. After the merge, fast-forward the
   primary checkout on `main`, which updates every linked consumer.
3. Before fast-forwarding, check `herdr pane list` and `pgrep -f "pending-watch.sh watch"`
   for running supervisors on the old layout. They keep working through the fallback and migrate
   on their next rebuild; name them to the operator.
4. Rollout: `~/personal/head-chief/install.sh --sync-settings --scan ~/personal`. Expect atoria,
   translate-side and tft-statistic in `~/supervisor/.installs`, and `~/supervisor` in each repo's
   `.claude/settings.local.json`. Run it again and confirm no file changes.
5. Journal entry in `plans/journals/`; mark the plan completed.

## Todo

- [x] PR merged
- [x] Rollout on 3 repos, idempotent re-run checked
- [x] Journal written, plan status completed

## Success Criteria

- `main` holds the merge, and both test files pass on `main`.
- The three consumer repos list `~/supervisor` in `settings.local.json`; a second sync changes nothing.
