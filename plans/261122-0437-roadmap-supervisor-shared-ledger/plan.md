---
title: "roadmap-supervisor: read only new answers, archive recorded ones, shared ~/supervisor folder"
description: "Stop the supervisor from re-reading answered decisions, keep the live ledger short, and let the operator answer every project from one folder."
status: completed
priority: P1
effort: 14h
branch: feat/roadmap-supervisor-shared-ledger
tags: [skill, shell, herdr, install, docs]
blockedBy: []
blocks: []
created: 2026-11-22
---

# roadmap-supervisor: new-answer reader, ledger archive, shared ~/supervisor folder

## Overview

After an operator edit, the supervisor reads the whole `pending-decisions.md`, including
every item answered long ago, because the format forbids deleting items. Each project also
keeps its ledger deep in `plans/…-supervisor/`, so the operator moves between repos to answer.

This plan adds script commands that print only newly answered items and that move a recorded
item into a project archive. It moves the live ledger to `~/supervisor/<project>--<session>.md`.
It also makes `install.sh` grant each repo access to that folder and back-fill repos that
already use the skill. Hooks are not used: an operator's editor save fires no Claude Code
tool event, and the watcher's `user-edit` exit already marks that moment.

Source: the advice confirmed on 2026-11-22 (`/ak-advise`). The operator's choices are in the
Validation Log.

## Phases

| # | Phase | Status | Depends on | Effort |
|---|---|---|---|---|
| 1 | [Read only new answers](phase-01-answer-reader.md) | done | none | 2h |
| 2 | [Record and archive answered items](phase-02-record-and-archive.md) | done | 1 | 3h |
| 3 | [Live ledger in ~/supervisor, with migration](phase-03-shared-ledger-folder.md) | done | 2 | 4h |
| 4 | [install.sh grants ~/supervisor per repo](phase-04-install-settings.md) | done | none | 3h |
| 5 | [Live trial under Herdr](phase-05-live-trial.md) | done | 3, 4 | 1h |
| 6 | [Publish and roll out (operator gate)](phase-06-publish-rollout.md) | done | 5 | 1h |

Phase 4 touches only `install.sh`, `tests/` and the README install section, so it can run in
parallel with phases 1–3. The README section on the ledger belongs to phase 3, and the two
edits must not overlap.

## Key constraint: work in a worktree

`atoria`, `translate-side` and `tft-statistic` link `.claude/skills/roadmap-supervisor` into
this checkout. The links follow the primary checkout's HEAD, so switching branches there
changes the skill for every running supervisor. Do all work in git worktrees. The primary
checkout stays on `main` and is fast-forwarded only after each merge.

## Acceptance criteria (Done means)

1. Test: a ledger holding one ANSWERED item, one OPEN unanswered item and one OPEN item with an
   answer. `pending-watch.sh answers <dir>` prints exactly the third item (header, question,
   options, `Chặn:`, answer) and nothing else.
2. `record <dir> D<n> <channel> [text]` stamps the answer, sets ANSWERED, appends the item to
   `<dir>/pending-decisions.archive.md`, removes it from the live file and syncs the hash. A
   restarted watcher does not wake for that write. A second `record` of the same item does not
   duplicate it in the archive. When the live file changed during `record`, nothing is written.
3. `add` assigns `D<max(live ∪ archive)+1>`, so a number is never reused.
4. `init` creates `~/supervisor/<project>--<session>.md` with a header (project, project path,
   supervisor session, Herdr tab and pane, start time, archive path) and writes
   `<dir>/ledger.path`. Every command resolves the ledger through `ledger.path` and falls back
   to `<dir>/pending-decisions.md`. `close` always moves the live file back into the project.
   When `<dir>/pending-decisions.md` already exists, `init` migrates it: OPEN items go to the
   shared file, ANSWERED items go to the archive, and the old file is kept as
   `pending-decisions.md.migrated`. No item is lost or duplicated.
5. `SKILL.md` and the references never tell the supervisor to read the whole ledger. They say to
   use `answers`, `list` and `line`.
6. `install.sh --project --skill roadmap-supervisor` creates `~/supervisor`, merges it into
   `<repo>/.claude/settings.local.json` `permissions.additionalDirectories` (backup, no
   duplicate entries) and records the repo in `~/supervisor/.installs`. `--sync-settings [--scan DIR]`
   re-applies this, and a second run changes nothing. `--uninstall` removes only that entry and
   that registry line.
7. `scripts/tests/test-pending-watch.sh` and `tests/test-install.sh` pass. README documents the folder,
   the commands and the install flags.
8. The live trial passes. After rollout, atoria, translate-side and tft-statistic each list
   `~/supervisor` in `.claude/settings.local.json`.

## Non-goals

- Claude Code hooks, symlinks into `~/supervisor`, an INDEX or dashboard file.
- Editing `~/.claude/settings.json`, cross-machine sync, or a change to the `D<n>` header format.
- Changes to `head-chief`, `managed-session` or other skills.

## Constraints

- The watcher still calls no model. Use only `bash`, `awk`, `sed`, `shasum`, `herdr`, plus `jq` in `install.sh`.
- Grant access per repo. Never write user-scope settings.
- One PR on branch `feat/roadmap-supervisor-shared-ledger`, with one conventional commit per phase.
- Conventional commits with no plan, phase or audit IDs in code, tests or commits. Stage with explicit `git add` paths.
- Stop every process you start, including test watchers.

## Validation Log

### Session 1 — 2026-11-22 (operator choices from `/ak-advise`, verbatim)

1. Recorded items go to: "Chuyển sang file lưu trữ (Recommended)".
2. Live ledger location: "File thật nằm ở ~/supervisor (Recommended)".
3. When the supervisor ends: "Luôn chuyển về project".
4. Where install grants access: "2, có cơ chế update lên repo đã cài skill sẵn nữa" (per-repo
   `settings.local.json`, plus a way to update repos that already have the skill).
5. Updating existing repos: "Registry + quét một lần (Recommended)".
6. Reframing and preview: "Đúng, tiếp tục tư vấn".

### Session 2 — 2026-11-22 (plan validation, verbatim)

1. Notification click: "Mở thẳng file của supervisor đó (Recommended)".
2. Delivery: "1 PR gộp".
3. Supervisors on the old layout: "init tự chuyển sang ~/supervisor".

### Verified during planning

- `jq` is at `/usr/bin/jq`.
- `.claude/settings.local.json` is git-ignored in `~/personal/agent/atoria`,
  `~/personal/agent/translate-side` and `~/personal/tft-statistic`. Only atoria already has the file.
- `find ~/personal -maxdepth 5 -path '*/.claude/skills/roadmap-supervisor' -type l` finds exactly those three repos.
- `~/supervisor` does not exist yet.
- `pending-watch.sh` `parse` skips every line before the first `## D` header, so a metadata
  header at the top of the ledger needs no parser change.

### Verified during delivery

- A running session picks up a changed `permissions.additionalDirectories` with no restart. In the
  live trial, a Write to `~/supervisor` went through unprompted right after `install.sh` changed
  `settings.local.json`, while a control directory was prompted. The `/add-dir` fallback stays in
  SKILL.md for the rare refused write.
- The Bash sandbox needs no separate entry: per the Claude Code settings docs, it may write to every
  directory in `additionalDirectories`. README records this.
- Live trial: `reports/live-trial.md`. Test suites: 35/35 in `test-pending-watch.sh` and 46/46 in
  `tests/test-install.sh`.

## Stop and ask only if

- A failure you cannot explain.
- `record` loses or duplicates an operator answer in any test, and the cause is not found.
- A change outside `skills/roadmap-supervisor/`, `install.sh`, `tests/`, `README.md`, or the three
  consumer repos' `.claude/settings.local.json`.
- Before the `git push` and before the PR merge (phase 6).
