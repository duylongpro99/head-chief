---
title: "roadmap-supervisor: pending-decisions ledger, no-model watcher, multi-repo install"
description: "Stop operator questions from being lost when worker reports push the supervisor chat, and install or update the skill across the repos that use it."
status: completed
priority: P1
effort: 9h
branch: feat/roadmap-supervisor-pending-ledger
tags: [skill, shell, herdr, install, docs]
blockedBy: []
blocks: []
created: 2026-11-17
---

# roadmap-supervisor: pending-decisions ledger and multi-repo install

## Overview

When five workers are running and the supervisor is waiting on the operator, a worker
report starts a new supervisor turn. The open question, whether it was asked through an
`AskUserQuestion` dialog or as chat text, is closed or scrolled away. Nothing records it, and
compaction drops it. This plan adds a durable `pending-decisions.md` ledger, a shell
watcher that does not call any model (tab badge `⏳N`, Herdr notifications, wake on operator
edits), the supervisor rules that use them, and an install/update path for the repos that
use the skill.

Source: the advice confirmed in this session (`/ak-advise`, 2026-11-17), plus the operator
answers recorded in the Validation Log below.

## Phases

| # | Phase | Status | Depends on | Effort |
|---|---|---|---|---|
| 1 | [Register roadmap-supervisor in the repo](phase-01-register-skill.md) | completed | none | 0.5h |
| 2 | [pending-watch.sh and its tests](phase-02-pending-watch-script.md) | completed | 1 | 3h |
| 3 | [Supervisor rules and ledger format](phase-03-skill-docs.md) | completed | 2 | 1.5h |
| 4 | [install.sh dependencies and install guide](phase-04-install-dependencies.md) | completed | 1 | 1.5h |
| 5 | [Live trial under Herdr](phase-05-live-trial.md) | completed | 2, 3 | 1h |
| 6 | [Publish: PR and merge (operator gate)](phase-06-publish.md) | completed | 4, 5 | 0.5h |
| 7 | [Roll out to atoria, translate-side, tft-statistic](phase-07-rollout.md) | completed | 6 | 1h |

Phases 2 and 4 touch disjoint files and may run in parallel after phase 1.

## Key constraint: work in a worktree

`atoria/.claude/skills/roadmap-supervisor`, `atoria/.claude/skills/managed-session`, and the
`pr-review-loop` links in `translate-side` and `tft-statistic` are symlinks into
`~/personal/head-chief/skills/`. They follow that checkout's current HEAD (see the header of
`install.sh`). Switching branches in the primary checkout changes the skill for every live
consumer. All implementation happens in a git worktree on
`feat/roadmap-supervisor-pending-ledger`. The primary checkout stays on `main` until phase 6
merges.

## Acceptance criteria (Done means)

1. `skills/roadmap-supervisor/` is tracked on `main`, listed in `README.md` and in the
   `skills.sh.json` grouping. `skills/head-chief/.env.mcp` stays untracked.
2. `skills/roadmap-supervisor/scripts/pending-watch.sh` exists, is executable, calls no model,
   and `skills/roadmap-supervisor/scripts/tests/test-pending-watch.sh` passes these cases:
   - a new entry produces a Herdr notification and the tab label `<base> ⏳1`;
   - an operator edit of `Answer:` makes the watcher exit 0 with reason `user-edit`;
   - a supervisor write followed by `--synced` does not make the watcher exit;
   - `Seen: [x]` stops notifications and removes the item from the ⏳ count and from `--line`;
   - an open item still unseen after the re-notify interval is notified again;
   - a malformed `## D` header produces an error notification and a non-zero `--line` exit;
   - stopping the watcher restores the base tab label and leaves `pgrep -f pending-watch` empty.
3. `SKILL.md`, `references/monitoring-and-operator-gate.md`, `references/brief-template.md`
   and a new `references/pending-decisions-format.md` describe how the ledger is used:
   - Start creates the ledger and starts the watcher;
   - every `AskUserQuestion` is written to the ledger first;
   - answers arrive as chat `D<n>: …` / `D<n> seen` or as file edits, and are recorded verbatim with the time;
   - each turn ends with the `--line` output while items are open;
   - rebuilding after compaction reads the ledger;
   - cleanup stops the watcher;
   - the final report lists every OPEN item, including seen ones;
   - workers may not write to the supervisor folder.
4. `./install.sh --skill roadmap-supervisor` also links `managed-session`, read from
   `metadata.requires` in the skill's frontmatter. `--uninstall` never removes a dependency.
   `README.md` documents install, update and uninstall for each of the three install
   methods: symlink per project, symlink global, and an `npx skills` copy.
5. A live trial under Herdr confirms that the watcher exit wakes the supervisor, including
   while an `AskUserQuestion` dialog is open. The result is recorded in the phase-05 report.
6. The branch is merged to `main` on GitHub after the operator approves, and the primary
   checkout is fast-forwarded.
7. `atoria`, `translate-side` and `tft-statistic` each have `roadmap-supervisor` and
   `managed-session` symlinked to `~/personal/head-chief/skills/`. The `translate-side` link
   no longer points into `general-cc-kit/skills/head-chief`.

## Non-goals

- Phone push notifications, a separate Herdr pane, or reprinting full questions each turn.
- Changes to `head-chief` or `managed-session` behaviour.
- A `--scan` command in `install.sh`. The operator chose a documented command instead.
- Updating or deleting the stale clone `general-cc-kit/skills/head-chief`.
- A global `~/.claude/skills` install.

## Constraints

- Use only `stat`, `shasum`, `awk`, `sed` and `herdr`. No new dependencies; `fswatch` is not installed.
- Poll every 5 s and re-notify every 30 min. Make both overridable by environment variable for tests.
- Answers are recorded verbatim with date and time. A worker report never marks an item ANSWERED.
- Use conventional commits with no plan, phase or audit IDs in code, tests or commits. Stage with explicit `git add` paths.
- Stop every process you start. The watcher is a tracked background process.

## Validation Log

### Session 1 — 2026-11-17 11:52 (operator answers, verbatim choice)

1. Register the skill in the repo: "Có, làm phase đầu (Recommended)".
2. install.sh additions: "Tự kèm dependency, Chỉ viết hướng dẫn". No `--scan`.
3. Stale clone used by translate-side: "Relink về checkout chính (Recommended)".
4. Push / npx update: "Có, hỏi tôi trước khi push (Recommended)".
5. Install targets: "atoria, translate-side, tft-statistic". No global install.

### Verified during planning

- `herdr notification show <TITLE> [--body] [--sound none|done|request]`, `herdr tab rename <TAB_ID> <LABEL>`,
  `herdr tab get`, and `herdr pane current` (JSON with `tab_id`) exist on this machine.
- `.claude/skills` is git-ignored in atoria, translate-side and tft-statistic, so
  `install.sh --project` will not refuse.
- No `npx skills` copy of any head-chief skill was found under `~/personal` (the only
  `skills-lock.json`, in `playground`, lists `teardown`).

### Unverified (each closed by a named phase)

- [UNVERIFIED] A `run_in_background` command exit wakes the supervisor while an
  `AskUserQuestion` dialog is open. Phase 5 closes this.
- [UNVERIFIED] `npx skills` accepts a `metadata.requires` frontmatter key. Phase 4 checks this
  with `npx skills add <local path> --list` or by reading the CLI docs. Fallback: a
  `requires:` comment line that `install.sh` reads.
- [UNVERIFIED] `herdr tab get <id>` output includes the current label, needed to restore the
  base name. Phase 2 checks this; fallback: record the base label passed as `--tab-label`.

## Stop and ask only if

- A background command exit does not wake the supervisor while a dialog is open (phase 5).
- `herdr` cannot rename or notify for the supervisor's own tab.
- Any change outside `skills/roadmap-supervisor/`, `install.sh`, `README.md`, `skills.sh.json`,
  or the three named consumer repos' `.claude/skills/` links.
- Before `git push` and before merging the PR (phase 6).
