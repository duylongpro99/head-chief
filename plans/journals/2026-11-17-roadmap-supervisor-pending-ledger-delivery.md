---
title: "roadmap-supervisor pending-decisions ledger: build, live trial, review fixes, rollout"
date: 2026-11-17
summary: "Delivered the ledger, no-model watcher and dependency-aware install in PR #4 (merged ed9960b); the live trial disproved the 'report closes the dialog' premise; 8 of 10 review findings fixed; rolled out to atoria, translate-side and tft-statistic."
---

# roadmap-supervisor pending-decisions ledger: build, live trial, review fixes, rollout

## What happened

Executed `plans/261117-1152-roadmap-supervisor-pending-ledger/plan.md` in `--auto` mode, in a
separate worktree so the primary checkout (which consumers symlink into) stayed on main.

- The skill was registered unchanged first, so later diffs show only the new behaviour.
- `pending-watch.sh` watches `pending-decisions.md` without a model: a `⏳N` tab badge,
  Herdr notifications with a 30-minute re-notify, a footer `line`, and an exit on any
  operator edit that `synced` did not account for. It is bash 3.2 compatible and tested
  with a stub `herdr`.
- `install.sh` now links the dependencies a skill lists under `metadata.requires`, and the
  README has an install, update and uninstall guide across repos.
- Merged as PR #4 (`ed9960b`) after two operator gates. The merge waited until the
  content-studio supervisor in atoria went idle. Rollout: atoria (already linked),
  translate-side (managed-session relinked away from the stale general-cc-kit clone),
  tft-statistic (new links). Git status was unchanged in each.

## What the live trial taught

The plan assumed that a worker report closes an open `AskUserQuestion` dialog. It does not.
While a dialog is open, cross-session messages and `run_in_background` exits both queue
until it closes. A file answer was detected by the watcher in 9 s, but the session stayed
asleep until the dialog closed. The operator chose to keep the dialog and fix the docs.
Without a dialog, a file answer was recorded 13 s after the edit.

A second, unplanned case appeared. The operator answered B in the dialog while the harness
had written A in the file. The supervisor, with no rule for this, recorded both on a
`Conflict:` line and asked in chat. That became the documented rule.

The supervisor also refused a fake worker report (commit absent) and refused peer claims
as operator authority. That is the behaviour wanted, and it made the harness's own
messages carry no weight.

## Review

An independent reviewer reproduced three high-priority bugs the 7 tests did not cover:
- A `Seen: [x]` edit with nothing to rewrite caused a wake loop every ~10 s.
- `synced` could absorb an operator answer saved just before a supervisor write.
- A stale pid let `stop` kill an unrelated process.

All three are fixed (`d119d6d`), along with CRLF, a scoped `pgrep`, a ledger written only
from Bash, and `install.sh` leaving an already-present dependency alone (`d3e7a65`). The
tests went from 7 to 10.

## Follow-up

- The watcher left running after its Claude session dies is fixed in PR #5 (`f3441f9`). The
  watcher records its owning `claude` process at start and exits with "owner gone" once that
  process is no longer alive. Test 11 covers it.
- The remote branch `feat/roadmap-supervisor-pending-ledger` has been deleted.

## Left open

- `install.sh` reads `requires:` only in its one-line form. The operator accepted this.
