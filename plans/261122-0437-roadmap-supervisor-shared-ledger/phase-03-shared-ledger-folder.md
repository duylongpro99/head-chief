---
title: "Phase 3: Live ledger in ~/supervisor"
status: done
---

# Phase 3: Live ledger in ~/supervisor

## Overview

Priority P1, 4h. Depends on phase 2. The live ledger becomes a real file in one shared
folder, so the operator answers every project from one place.

## Requirements

- `SUPERVISOR_HOME` (default `$HOME/supervisor`) is the shared folder; tests override it.
- Ledger resolution for every command: `<dir>/ledger.path` (one absolute path) when present,
  else `<dir>/pending-decisions.md`. The archive and `.pending-state/` stay in `<dir>`.
- `init <dir> --session <name> [--project <name>] [--tab <id>] [--pane <id>]`:
  - the project root is the git root of `<dir>`, and the project name defaults to its basename;
  - the file is `$SUPERVISOR_HOME/<project>--<session>.md`, with the folder created if missing;
  - the header looks like this, and none of its lines start with `## `:
    ```text
    # Pending decisions
    Project: <name> · <abs project root>
    Supervisor: <session> · Herdr tab <tab> · pane <pane>
    Started: <YYYY-MM-DD HH:MM> · Archive: <abs archive path>
    ```
  - the tab and pane default to `herdr pane current`;
  - when the file exists with the same `Project:` path, reuse it (a restart or compaction);
    when it exists with a different path, exit 1 and name both paths;
  - migrate when `<dir>/pending-decisions.md` already exists: stop the watcher if it is running;
    append ANSWERED items to the archive, skipping IDs it already holds; copy OPEN items (unseen,
    seen and answered-but-unrecorded) unchanged, in order, under the new header; then rename the
    old file to `pending-decisions.md.migrated`. Build the new file and the archive first and
    rename last, so a failure leaves the old file in place. Print how many items moved where, and
    any answered-but-unrecorded IDs, which the supervisor then handles with `answers` and `record`;
  - write `ledger.path`, sync, and print the ledger path.
- `close <dir>`: stop the watcher if it is running, move the live file to
  `<dir>/pending-decisions.final.md`, point `ledger.path` at it, sync, and print the path.
  `line` and `list` keep working on the moved file.
- Notifications: the click opens the live ledger file (its `file://` URL), and the message's
  last line shows that path.
- `line` prints the resolved ledger path.

## Implementation Steps

1. Replace the fixed `LEDGER=` with a `resolve_ledger()` function, and keep `STATE` in `<dir>`.
2. Add `cmd_init` and `cmd_close`. Make `dir_url` take a path argument.
3. Tests (with `SUPERVISOR_HOME` set to a temp dir):
   - `init` writes the header and `ledger.path`; `watch` and `line` then use the shared file;
   - `init` twice for the same project reuses the file; a different project with the same name is refused;
   - migration: an old ledger with ANSWERED, OPEN-unseen, OPEN-seen and OPEN-answered items ends with
     the ANSWERED item in the archive, the three OPEN items in the shared file in order, the
     `.migrated` file present, and `answers` printing the answered one;
   - migration run twice (a crash before the rename) does not duplicate archive items;
   - the old layout without `ledger.path` still passes the existing cases;
   - `close` moves the file, `ls $SUPERVISOR_HOME` no longer shows it, and `list` still reads it;
   - the notification `-open` argument is the ledger file URL.
4. Docs:
   - `SKILL.md` Start step 3: create `briefs/`, `sessions.md` and `follow-ups.md`, then `init`
     (no in-project `pending-decisions.md`), then start the watcher. If a write to `~/supervisor`
     is refused, run `/add-dir ~/supervisor` or re-run `install.sh --sync-settings`;
   - Stopping: run `close` after `stop`; the final report names `pending-decisions.final.md`;
   - Gotchas and compaction: read `ledger.path`, then use `list` and `answers`. When
     `ledger.path` is missing but `pending-decisions.md` exists (a supervisor started before this
     change), run `init` to migrate, then restart the watcher. Supervisors that do not re-read
     SKILL.md keep working on the old layout through the fallback until they do;
   - `pending-decisions-format.md`: location, header, archive and final file;
   - `brief-template.md`: forbidden paths include `~/supervisor/`;
   - README: a short section describing the folder.

## Todo

- [x] resolve_ledger, init, close, notification target
- [x] 8 new test cases pass; the full test file passes
- [x] SKILL.md, references, brief template and README updated

## Success Criteria

- During a run, `ls ~/supervisor` shows `<project>--<session>.md`. After `close` it does not, and
  the project folder holds `pending-decisions.final.md` and the archive.

## Risk

- Migration while the operator is editing the old file: it is a compare and swap on the old file,
  and on a change it exits 3 and writes nothing.
- Two supervisors with the same project and session names. Session names are unique per Herdr
  workspace, so `init` reuses the file only when the project path matches too.
- A project path with spaces or non-ASCII characters: quote every path, and reuse the existing
  percent-encoding in `dir_url`.
