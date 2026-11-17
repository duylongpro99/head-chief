---
title: Plan roadmap-supervisor pending-decisions ledger
date: 2026-11-17
summary: "Planned a durable operator-question ledger with a no-model watcher, install.sh dependency expansion, and rollout to three consumer repos"
---

# Plan roadmap-supervisor pending-decisions ledger

## What happened
In roadmap-supervisor, worker reports start a new supervisor turn. That turn closes an open AskUserQuestion dialog or scrolls chat questions out of view, and compaction then drops them. An advisory interview settled on a fix, and it became the plan at `plans/261117-1152-roadmap-supervisor-pending-ledger/`.

## Findings
- `skills/roadmap-supervisor/` is still untracked on main (95313bc), but atoria already symlinks to it.
- The consumers (atoria, translate-side, tft-statistic) symlink into the primary checkout `~/personal/head-chief`, so switching branches there changes the skill for every live supervisor. The plan therefore requires the work to happen in a worktree.
- translate-side's managed-session points into a stale clone (`general-cc-kit/skills/head-chief`, 992308b).
- No `npx skills` copies of head-chief skills were found under `~/personal`.

## Decision
- Add a `pending-decisions.md` ledger as the record of every operator question. It is written before AskUserQuestion is called, and the operator can answer by typing `D<n>: …` in chat or by editing the file.
- Add `pending-watch.sh`, which calls no model. It polls with stat and shasum every 5 s, shows a `⏳N` badge on the Herdr tab, sends a notification immediately and again every 30 min, and exits when the operator edits the file, which wakes the supervisor. Marking an item seen removes it from the badge and the footer line.
- install.sh expands `metadata.requires`, so installing roadmap-supervisor also links managed-session. There is no `--scan` command; the README documents a find command instead.
- Relink translate-side to the primary checkout. Pushing and merging both require the operator's approval first.

## Next steps
- Execute with `/ak:cook plans/261117-1152-roadmap-supervisor-pending-ledger/plan.md`.
- Phase 5 must confirm that the exit of a background command wakes the supervisor while a dialog is open.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
