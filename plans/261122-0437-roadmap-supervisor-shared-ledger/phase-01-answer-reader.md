---
title: "Phase 1: Read only new answers"
status: done
---

# Phase 1: Read only new answers

## Overview

Priority P1, 2h. This phase adds `pending-watch.sh answers` and `list`, and rewrites the
docs so the supervisor never reads the whole ledger. It alone removes most of the re-reading.

## Context

- `skills/roadmap-supervisor/scripts/pending-watch.sh`: `parse()` emits one record per item.
  `cmd_synced` already finds OPEN items whose `Answer:` has text.
- `references/monitoring-and-operator-gate.md` "Handling answers" says "read `pending-decisions.md`".
- `references/pending-decisions-format.md` defines items, states and parser rules.

## Requirements

- `answers <dir>`: print the full block of every item whose header is OPEN and whose `Answer:`
  has text. The block runs from its `## D` line up to the next `## ` line, with trailing blank
  lines dropped, and items are separated by one blank line. Print nothing when there are none.
  Exit 2 on a malformed `## D` header, the same as `line`.
- `list <dir>`: print one line per OPEN item, `D<n> · <scope> · <unseen|seen|answered> · <question>`,
  for the final report and for rebuilding after compaction. Nothing when there are none.
- Neither command writes anything.

## Implementation Steps

1. Add an awk function `blocks()` that prints item blocks for a given set of IDs. Reuse `parse()`
   for selection, so the parser rules are not duplicated.
2. Add `cmd_answers` and `cmd_list`, the `case` entries and the usage header lines.
3. Tests in `scripts/tests/test-pending-watch.sh`:
   - one ANSWERED item, one OPEN unanswered item and one OPEN answered item: `answers` prints only
     the third, including its options and `Chặn:` line;
   - a multi-line answer is printed whole;
   - an empty ledger prints nothing and exits 0;
   - a malformed header makes `answers` exit 2;
   - `list` marks unseen, seen and answered correctly.
4. Docs:
   - `monitoring-and-operator-gate.md` "Handling answers": after a `user-edit` exit, run `answers <dir>`; never Read the ledger.
   - `pending-decisions-format.md`: document `answers` and `list` under "Watcher commands".
   - `SKILL.md` Gotchas and the compaction rebuild: use `list` and `answers`, not a Read of the file.
   - Final report: build the OPEN list from `list`.

## Todo

- [x] `answers` and `list` in pending-watch.sh
- [x] 5 new test cases pass; the full test file passes
- [x] Docs no longer tell the supervisor to read the ledger (`grep -n "read \`pending-decisions.md\`"` finds nothing)

## Success Criteria

- `bash skills/roadmap-supervisor/scripts/tests/test-pending-watch.sh` passes.
- The 3-item case prints exactly one block.

## Risk

- A block boundary bug could print a neighbouring item. Cover it with an item directly after the
  answered one, with no blank line between them.
