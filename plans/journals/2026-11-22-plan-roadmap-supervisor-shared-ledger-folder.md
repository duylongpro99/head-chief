---
title: "Plan: roadmap-supervisor shared ledger folder"
date: 2026-11-22
summary: "Planned new-answer reader, ledger archive, ~/supervisor shared folder and per-repo install access"
---

# Plan: roadmap-supervisor shared ledger folder

## What happened
After using the file-answer flow of roadmap-supervisor, the operator reported two problems:
- the supervisor re-reads the whole `pending-decisions.md`, old answered items included, because the format forbids deleting items;
- answering supervisors across several projects means moving between repos.

An `/ak-advise` session settled the scope. Then `/ak-plan` produced
`plans/261122-0437-roadmap-supervisor-shared-ledger/` with 6 phases (14h).

## Decision
- No Claude Code hook. An editor save fires no tool event, and the watcher's `user-edit` exit already marks the moment.
- New `pending-watch.sh` commands:
  - `answers` prints only newly answered items;
  - `list` gives one line per OPEN item;
  - `add`, `record` and `seen` write the ledger with compare and swap (exit 3 when the file changed).
- Recorded items move to `<dir>/pending-decisions.archive.md`. `D<n>` is the highest number in the live file and the archive, plus 1.
- The live ledger is a real file at `~/supervisor/<project>--<session>.md`:
  - `init` creates it with a metadata header and writes `ledger.path`;
  - `init` migrates an old in-project ledger;
  - `close` always moves the file back into the project.
- A desktop notification click opens the ledger file.
- `install.sh --project` grants `~/supervisor` in each repo's `.claude/settings.local.json` and keeps a registry in `~/supervisor/.installs`. `--sync-settings --scan` back-fills repos that already have the skill.
- Delivery is one PR, with operator approval before the push and before the merge.

## Next steps
- Run `/ak:cook` on the plan, in a worktree. The consumer symlinks follow the primary checkout's HEAD.
- Two items are unverified and get checked in phase 4 and phase 5:
  - whether a running session picks up a changed `additionalDirectories`;
  - whether the Bash sandbox needs its own write allowance for `~/supervisor`.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
