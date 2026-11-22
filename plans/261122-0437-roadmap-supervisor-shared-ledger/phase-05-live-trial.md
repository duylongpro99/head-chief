---
title: "Phase 5: Live trial under Herdr"
status: done
---

# Phase 5: Live trial under Herdr

## Overview

Priority P1, 1h. Depends on phases 3 and 4. Confirm the whole loop with a real supervisor
session, two projects and a real Herdr tab, and close the unverified items.

## Steps

1. From the feature worktree, run `install.sh --project --skill roadmap-supervisor` into two scratch
   git repos, with `.claude/` ignored, under `~/personal/tmp-supervisor-trial-{a,b}`. Their links
   point at the worktree, not the primary checkout.
2. In each repo, start a Claude session under Herdr and have it run Start up to the watcher, with
   no workers. Confirm `ls ~/supervisor` shows two files with correct headers.
3. In repo A, `add` two items. In repo B, `add` one item. Answer one of A's items in the editor
   and save.
   - Expect A's watcher to exit `user-edit` and A's supervisor to run `answers`, which prints
     only that item; the transcript shows no Read of the ledger.
   - Expect A to run `record`: the item moves to the archive and the watcher restarts without waking again.
4. Answer B's item through chat `D1: A`, and check `record ... chat`.
5. While the session is running, check whether it can write `~/supervisor` right after `install.sh`
   changed `settings.local.json`, with no restart. Record yes or no; on no, confirm `/add-dir`
   works and that the SKILL.md wording matches.
6. Click a desktop notification and confirm it opens the live file.
7. Migration: in a third scratch folder, create an old-layout `pending-decisions.md` with one
   ANSWERED, one OPEN-unseen and one OPEN-answered item, and start a watcher on it. Run `init` and
   confirm the item split, the `.migrated` file, the stopped old watcher, and that `answers` shows
   the answered item.
8. `close` both. `ls ~/supervisor` shows only `.installs`, and each project holds `.final.md` and the archive.
9. Clean up: stop both sessions, `pgrep -f pending-watch` is empty for the trial folders,
   `install.sh --uninstall --project` in both repos, and delete the scratch repos.

## Output

`plans/261122-0437-roadmap-supervisor-shared-ledger/reports/live-trial.md` with each step's result,
the answers to the two unverified items, and any doc change made because of them.

## Todo

- [x] Steps 1–9 done and recorded
- [x] Unverified items in plan.md marked verified or replaced by the fallback

## Success Criteria

- Every expectation in steps 2–8 holds, and nothing from the trial is left running or installed.
