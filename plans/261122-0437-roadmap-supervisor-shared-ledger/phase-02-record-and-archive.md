---
title: "Phase 2: Record and archive answered items"
status: done
---

# Phase 2: Record and archive answered items

## Overview

Priority P1, 3h. Depends on phase 1. Once an answer is recorded, its item leaves the live
file. The script takes over every supervisor write to the ledger, so the rule "write only from
Bash and run `synced` in the same call" is no longer needed for normal use.

## Requirements

- `add <dir>`: read one item body from stdin (scope on the first line, then the question,
  options, `Chặn:`), assign `D<n>` = highest number in live ∪ archive + 1, write the header with
  OPEN and the current time, append `Seen: [ ]` and `Answer:`, append to the live file, sync,
  and print `D<n>`.
- `record <dir> D<n> <dialog|chat|file> [text]`:
  - for `file` the answer is the text already in the item; for `dialog` and `chat` the text argument is required;
  - the archived item gets `Answer: <YYYY-MM-DD HH:MM> (<channel>) <first line>`, with any
    further answer lines kept below it, and its header set to ANSWERED;
  - the item is appended to `<dir>/pending-decisions.archive.md`, which is created with the title
    `# Answered decisions` when missing, unless the archive already holds `## D<n> ·`; then the append is skipped;
  - the item is removed from the live file, the new hash is stored (synced), and the ID is printed.
- `seen <dir> D<n>`: set `Seen: [x]` and sync, for chat `D<n> seen`.
- Compare and swap for every writer (`add`, `record`, `seen`): hash the live file, build the new content in a
  temp file in the same folder, re-hash the live file, and `mv` only when it is unchanged. When it
  changed, write nothing, exit 3 and print `pending-watch: ledger changed; run answers again`.
- Write the archive before swapping the live file. A crash in between leaves the item in both
  files, and a rerun is safe because the archive check skips the duplicate.
- An unknown `D<n>`, or an item that is not OPEN, exits 1 with a clear message.
- Update the script header: the script now writes the ledger, only through these commands.

## Implementation Steps

1. Add `max_id()` over the live file and the archive, and `rewrite_ledger()`, a temp-file
   compare and swap that takes an awk program.
2. Add `cmd_add`, `cmd_record` and `cmd_seen`, and route them in `case`.
3. Tests:
   - `record` moves the item, the archive gains it, and the live file loses it; a watcher started
     before the call does not exit;
   - running `record` twice archives the item once;
   - the live file changing between read and swap (inject with a test hook env var, e.g.
     `PENDING_TEST_BEFORE_SWAP`) gives exit 3 and leaves both files unchanged;
   - `add` after D3 has been archived returns D4;
   - a multi-line file answer is preserved;
   - `seen` sets `[x]` and removes the item from `line`.
4. Docs:
   - `pending-decisions-format.md`: archive file, the four states (ANSWERED now appears only in
     the archive), the new commands, and that the ledger is written only through `add`, `record`
     and `seen` (manual Bash plus `synced` only for a `Conflict:` line);
   - `monitoring-and-operator-gate.md` "Operator gate" and "Handling answers": use `add`, then
     `AskUserQuestion`; on an answer use `record`; on a mark use `seen`; on exit 3 run `answers`
     again;
   - `SKILL.md` operator gate paragraph.

## Todo

- [x] add / record / seen with compare and swap
- [x] 6 new test cases pass; the full test file passes
- [x] Docs updated; "never delete an item" now reads "items move to the archive, numbers are never reused"

## Success Criteria

- The live file never holds an ANSWERED item after `record`.
- No test loses or duplicates an answer.

## Risk

- An editor with an unsaved buffer can save over the swapped file and bring the item back.
  `answers` then shows it again because it is still OPEN with an answer; `record` skips the archive
  duplicate and removes it again. Document this in the format doc.
- The temp file must be in the same folder as the ledger so `mv` is atomic.
