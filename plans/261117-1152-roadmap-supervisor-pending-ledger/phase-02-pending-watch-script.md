---
phase: 2
title: pending-watch.sh and its tests
status: completed
effort: 3h
depends_on: [1]
---

# Phase 2: pending-watch.sh and its tests

## Context

The ledger lives at `<supervisor-dir>/pending-decisions.md`, inside the supervisor's plan
folder. The script owns every signal that must not cost a model turn: the tab badge,
notifications with 30-minute reminders, and waking the supervisor when the operator edits the
file. The supervisor runs the script with `run_in_background`; when the script exits, the
harness wakes the session.

Herdr commands verified on this machine:
- `herdr pane current` returns JSON with `.result.pane.tab_id`;
- `herdr tab rename <TAB_ID> <LABEL>`;
- `herdr notification show <TITLE> --body <TEXT> --sound request`.

## Ledger format (the parser contract; phase 3 documents it for humans)

```text
## D3 · M5 · OPEN · 2026-11-17 11:40
Câu hỏi: Judge model cho visual check?
- A (đề xuất): flash — 40–90 s/lần
- B: qwen3.8-max — 227–811 s/lần
Chặn: M5-cook
Seen: [ ]
Answer:
```

- Header regex: `^## D[0-9]+ · [^·]+ · (OPEN|ANSWERED) · [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$`.
  Any other line starting with `## D` is malformed.
- An item is *open* when its status is OPEN and `Answer:` is empty. It is *counted* when it is
  open and has `Seen: [ ]`. A non-empty `Answer:` under an OPEN header counts as an operator
  answer that the supervisor has not processed yet.

## Interface

```text
pending-watch.sh watch  <dir> [--tab <tab-id>] [--base-label <label>]
pending-watch.sh synced <dir>      # supervisor calls this after every write it makes
pending-watch.sh line   <dir>      # prints the one-line footer, or nothing when the count is 0
pending-watch.sh stop   <dir>      # stops a running watcher, restores the tab label
```

- State lives in `<dir>/.pending-state/`:
  - `hash`: the hash of the supervisor's last write;
  - `pid`;
  - `tab`, `base-label`;
  - `notified/<Dn>`: the epoch of the last notification for that item.

  The script never writes `pending-decisions.md`.
- `watch` records its PID and resolves the tab from `herdr pane current` when `--tab` is
  absent. It reads the base label with `herdr tab get` and falls back to `--base-label`; it
  fails loudly if neither works. Then it loops every `PENDING_POLL_SECONDS` (default 5):
  1. compute `shasum -a 256` of the ledger;
  2. if the hash differs from `hash` and is unchanged on the next tick, print
     `pending-watch: user-edit` and exit 0;
  3. otherwise recount and rename the tab to `<base> ⏳N`, or to `<base>` when N is 0. Rename
     only when the label changes;
  4. for each counted item with no `notified/<Dn>`, run `herdr notification show "⏳ <Dn> mới" --body <question line>`;
     for each one whose last notification is older than `PENDING_RENOTIFY_SECONDS` (default 1800),
     run `"⏳ <Dn> vẫn chờ"`;
  5. on a malformed header, notify once, `pending-watch: malformed header '<line>'`.
- `watch` traps TERM and INT: it restores the base label, removes `pid`, and exits.
- `line` prints `⏳ N đang chờ bạn (D1, D3 mới) → <abs path>`, where an item is "mới" when it has
  never been notified. It appends ` (watcher off)` when `pid` is missing or dead. It exits 2 on a
  malformed header.
- `synced` writes the current hash.
- `stop` sends TERM to `pid`, waits up to 5 s, and escalates to KILL only if the process ignores TERM.

## Files

- Add: `skills/roadmap-supervisor/scripts/pending-watch.sh` (mode 755)
- Add: `skills/roadmap-supervisor/scripts/tests/test-pending-watch.sh` (mode 755)

## Tests

`test-pending-watch.sh` puts a stub `herdr` first on `PATH`. The stub appends its arguments
to a log file and answers `pane current` and `tab get` with fixed JSON. The test sets
`PENDING_POLL_SECONDS=1 PENDING_RENOTIFY_SECONDS=3`, uses a temp folder under
`${TMPDIR}`, and kills any leftover watcher in an EXIT trap. It covers the seven cases in
plan.md acceptance criterion 2. Wait for conditions with bounded retry loops, not fixed
sleeps.

## Steps

1. Run `herdr tab get <tab-id>` on the real Herdr and record whether a label field exists.
   Adjust the base-label lookup to match.
2. Write the script with `set -euo pipefail` and quoted paths. Run `shellcheck` if it is
   installed; otherwise run `bash -n`.
3. Write the test and run it until it passes 3 times in a row.
4. Commit `feat(roadmap-supervisor): add pending-decisions watcher with tab badge and reminders`.

## Validation

- `bash skills/roadmap-supervisor/scripts/tests/test-pending-watch.sh` prints `7/7 passed` and exits 0.
- `pgrep -f pending-watch` is empty after the test.
- `grep -nE 'claude|anthropic|ScheduleWakeup' scripts/pending-watch.sh` finds nothing, which shows the script does not call a model.

## Risk and rollback

- Editors that write through a temp file and rename: hashing the content, not the mtime,
  handles this.
- A race when the supervisor writes and calls `synced` more than one tick later: the 2-tick
  stability check gives about 10 s. Phase 3 requires `synced` to run in the same Bash call as
  the write.

Rollback: revert the commit.
