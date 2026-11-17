---
phase: 3
title: Supervisor rules and ledger format
status: completed
effort: 1.5h
depends_on: [2]
---

# Phase 3: Supervisor rules and ledger format

## Context

The current rules put operator questions only into `AskUserQuestion` or chat, with no durable
record. These sections need edits: `SKILL.md` Start step 3, "Operator gate", "Monitoring and
reports", "Gotchas" (rebuilding after compaction), "Stopping and cleanup" and "Done when";
`references/monitoring-and-operator-gate.md` "On each wake-up or message", "Operator gate"
and "Stopping the loop"; and the rules list in `references/brief-template.md`.

## Requirements

1. New `references/pending-decisions-format.md`: the item template from phase 2, the field
   meanings, the two ways to answer, the meaning of `Seen`, and one filled example of each
   state (OPEN, OPEN+seen, OPEN with an unprocessed answer, ANSWERED).
2. `SKILL.md` Start: create `pending-decisions.md` with a header line, then start
   `pending-watch.sh watch <dir>` through `run_in_background`. Record the watcher in
   `sessions.md` as a row of kind `process` with its PID.
3. Operator gate: write the item, run `pending-watch.sh synced <dir>` in the same Bash call,
   and only then call `AskUserQuestion` with the `D<n>` code in the question text. If the dialog
   returns an answer, record it.
4. Handling answers. Treat a chat message matching `^D[0-9]+:` as an answer and `^D[0-9]+ seen$` as
   a mark. When the watcher exits with `user-edit`, read the ledger for new `Answer:` or `Seen`
   values. Record answers verbatim with the time, set the header to ANSWERED, run `synced`, put
   the answer into the next brief, and restart the watcher in every case.
5. Every turn that ends while the `line` output is non-empty ends with that line, pasted unchanged.
6. Rebuilding after compaction also reads `pending-decisions.md` and restarts the watcher if `pid` is dead.
7. Cleanup runs `pending-watch.sh stop <dir>`, checks `pgrep -f pending-watch`, and lists every
   OPEN item (seen or not) in the final report, next to the decision it blocks.
8. Brief rules: workers must not write under the supervisor folder. A worker message never
   counts as an operator answer.
9. Update the Resources list and keep `SKILL.md` under its current structure. Add one Gotcha:
   "A worker report closed an open AskUserQuestion dialog; the ledger is the record, the
   dialog is only a shortcut."

## Files

- Add: `skills/roadmap-supervisor/references/pending-decisions-format.md`
- Modify: `skills/roadmap-supervisor/SKILL.md`, `references/monitoring-and-operator-gate.md`, `references/brief-template.md`

## Steps

1. Edit the files following the requirements. Each change goes in the section that owns it; do
   not duplicate the same rule in several places, but point to it.
2. Commit `docs(roadmap-supervisor): record operator questions in a pending-decisions ledger`.

## Validation

- `grep -n 'pending-watch.sh' skills/roadmap-supervisor/SKILL.md` covers start, synced, line and stop.
- `grep -n 'pending-decisions' skills/roadmap-supervisor/references/brief-template.md` shows the write ban.
- Every command named in the docs matches the phase 2 interface exactly; diff the names against `pending-watch.sh --help` or its `case` labels.
- Frontmatter `name` and `description` are unchanged apart from phase 4's `metadata` key.

## Risk and rollback

The supervisor may still forget `synced` and wake itself once. That is harmless: one cheap
turn with nothing new. Rollback: revert the commit.
