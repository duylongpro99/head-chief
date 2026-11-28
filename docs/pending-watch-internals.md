# pending-watch.sh internals

Maintainer notes for `skills/roadmap-supervisor/scripts/pending-watch.sh`, the no-model
watcher and only writer of the roadmap supervisor's pending-decisions ledger. What a
supervisor must do with the ledger is in
[`pending-decisions-format.md`](../skills/roadmap-supervisor/references/pending-decisions-format.md);
this file holds the rest. Tests: `bash skills/roadmap-supervisor/scripts/tests/test-pending-watch.sh`.

## Files and layouts

The live ledger, `ledger.path`, the archive and the final ledger are described in the
reference. In addition:

- Old layout: `<supervisor-dir>/pending-decisions.md`, used when `ledger.path` is missing.
  `init` migrates it and keeps it as `pending-decisions.md.migrated`.
- The archive is created with the title `# Answered decisions`.
- The archive and the state always stay in `<supervisor-dir>`; only the live ledger lives in
  `$SUPERVISOR_HOME`.

## init

`init <supervisor-dir> --session <name>` creates the live ledger with this header:

```text
# Pending decisions
Project: atoria · /Users/me/personal/agent/atoria
Supervisor: atoria-sup · Herdr tab w1:t3 · pane w1:p7
Folder: /Users/me/personal/agent/atoria/plans/261122-1000-x-supervisor
Started: 2026-11-22 10:05 · Archive: /Users/me/personal/agent/atoria/plans/261122-1000-x-supervisor/pending-decisions.archive.md
```

The project is the git root of `<supervisor-dir>`; outside git, the nearest folder above it
that holds `.claude` (never `$HOME`, whose `.claude` is the user's own), else the supervisor
folder itself. The project name defaults to that folder's name, and the tab and pane to
`herdr pane current`; `--project`, `--tab` and `--pane` override them. No header line starts
with `## `, so the parser skips the header. `init` reuses an existing file only when its
`Project:` and `Folder:` lines name this project and this supervisor folder (a rebuild after
compaction), and refuses one that belongs to another project or folder.

**Migration.** `init` migrates an old in-project `pending-decisions.md`, and the final ledger
of a supervisor started again after `close`, so its OPEN items are asked again under the same
numbers. It stops the watcher, appends ANSWERED items to the archive, copies OPEN items
unchanged and in order into the live ledger, and renames the old file to `<name>.migrated`
last, so a failure leaves it in place. A rerun after a crash copies no item twice. An operator
save during the migration makes it exit 3 with nothing written. It names OPEN items that
already have an answer in the file, for `answers` and `record`.

## close

`close` stops the watcher, moves the live ledger to `pending-decisions.final.md` (with a time
suffix when that name is taken) and points `ledger.path` at it, so `list` and `line` still
work. `~/supervisor` then holds only the ledgers of running supervisors. Running `close` again
prints the final path and changes nothing.

## Numbering

The file starts with the header, followed by items in order of `D<n>`. `add` numbers past the
highest `D<n>` in the live ledger, the archive, every final ledger and an old in-project
ledger, so a number is never reused: `D<n>` codes are what the operator types.

## Parser rules

| Field | Rule |
|---|---|
| Header | Must match `^## D[0-9]+ · <scope> · (OPEN\|ANSWERED) · YYYY-MM-DD HH:MM$`, with ` · ` (space, middle dot U+00B7, space) between fields. Any other line starting with `## D` is malformed: the watcher notifies an error, and `line`, `answers` and `list` exit 2 and write nothing. |
| First non-empty line | The question, used as the notification body. Its label (`Câu hỏi:`, `Question:`) is free. |
| Option and `Chặn:` lines | Free text |
| `Seen:` | `[x]` or `[X]` marks the item seen |
| `Answer:` | Empty means unanswered. Text after `Answer:`, or any non-blank line after it before the next `## ` line, counts as an answer. |
| `Conflict:` | Ignored |

The parser counts an item (badge, footer, reminders) when its header says OPEN, `Answer:` is
empty and `Seen:` is not marked; it reports an item as answered but unprocessed when its
header says OPEN and `Answer:` has text. ANSWERED appears only in the archive. CRLF line
endings are accepted.

`answers` prints each block from its `## D` line up to the next `## ` line, without trailing
blank lines, with one blank line between blocks.

### State examples

OPEN, waiting (counted):

```text
## D1 · p02 · OPEN · 2026-11-17 11:20
Câu hỏi: Giữ ngưỡng 0.95 hay hạ xuống 0.93?
- A (đề xuất): giữ 0.95, sửa trang mẫu — 1 phiên cook ~20 phút
- B: hạ 0.93 — bad.html (0.9718) sẽ lọt
Chặn: p02-cook
Seen: [ ]
Answer:
```

OPEN and seen:

```text
## D2 · M5 · OPEN · 2026-11-17 11:31
Câu hỏi: Đồng bộ skill mirror sang Hermes tối nay?
- A (đề xuất): sau khi job 21:00 xong
- B: ngay bây giờ — job đang chạy sẽ đọc file đổi giữa chừng
Chặn: none
Seen: [x]
Answer:
```

OPEN with an unprocessed answer (the operator edited the file; the watcher exited):

```text
## D3 · M5 · OPEN · 2026-11-17 11:40
Câu hỏi: Judge model cho visual check?
- A (đề xuất): flash — 40–90 s/lần
- B: qwen3.8-max — 227–811 s/lần
Chặn: M5-cook
Seen: [ ]
Answer: A, nhưng ghi số đo vào report
```

ANSWERED (written by `record`, in the archive):

```text
## D3 · M5 · ANSWERED · 2026-11-17 11:40
Câu hỏi: Judge model cho visual check?
- A (đề xuất): flash — 40–90 s/lần
- B: qwen3.8-max — 227–811 s/lần
Chặn: M5-cook
Seen: [ ]
Answer: 2026-11-17 11:52 (file) A, nhưng ghi số đo vào report
```

## Writes

`add`, `record` and `seen` build the new file from a snapshot and replace the ledger with an
atomic `mv` only when it still matches the snapshot; otherwise they write nothing and exit 3.
The check and the replace are two steps, so a save in the same instant can still be
overwritten; the window is a few milliseconds. Each stores the new hash in the state folder,
so the watcher does not wake for it, and names on stderr any other answer still waiting in
the file. After a successful `add`, when no live watcher is recorded for the folder, `add`
also warns on stderr with the full `watch` command line (absolute paths, shell-quoted).

`record` sets the header to ANSWERED and stamps the time and channel. An item whose `Answer:`
line was deleted still gets one in the archive.

**Crash recovery.** `record` writes the archive before it replaces the live file. A crash in
between, or an operator save that lands after the archive write, leaves the item in both
files. Running the same `record` again removes it from the live file and does not copy it
twice, as long as the archive copy holds the same answer. When the operator has changed the
answer since, `record` refuses (exit 1) and changes nothing.

**Stale editor buffer.** An editor that still holds the old file in an unsaved buffer can save
it over the new one. That brings back recorded items and removes items added since. A
brought-back item with a file answer shows up in `answers`, and `record ... file` removes it
again. A brought-back `dialog` or `chat` item has an empty `Answer:`, so the operator is asked
again; record the answer from the archive with the same channel and text. Re-add any item that
disappeared, with `add`.

## Operator actions

`<supervisor-dir>/operator-actions.md` lists steps only the operator can run. It is not part
of the ledger: the watcher does not watch it, and the operator never edits it (they reply in
chat). `action-add` and `action-done` are its only writers; each writes a temp file in the
folder and renames it over the old one.

- Header: `## A<n> · OPEN|DONE · YYYY-MM-DD HH:MM · <title>`. The body is the supervisor's
  file after its title line, then `Reply: A<n> done (or say what failed)`. `action-done`
  changes OPEN to DONE and appends `Done: <time> <the operator's words>` to the block.
- Numbers come from the highest `A<n>` in the file, which keeps DONE entries, so a number is
  never reused.
- `line` prints `🛠 N việc bạn cần tự làm (A1, …) → <file>` first, then ` · ` and the
  decisions part, so a line with decisions still ends with `(watcher off)` when no watcher
  runs.

## Secret check

`add` and `action-add` pass the body through `secret-scan.sh` and exit 1 on a hit, naming the
line and kind only. The scanner looks for shaped values (private-key headers, AWS, GitHub,
Slack, `sk-`, Google and Supabase keys, JWTs, `scheme://user:password@`), and skips
placeholder passwords in URLs. It cannot recognise a bare password.

## Watcher

`watch` polls every `PENDING_POLL_SECONDS` (default 5). When the ledger hash differs from the
stored one, it waits one more poll so a half-saved file is not read, then exits 0 with
`pending-watch: user-edit` as its first line, followed by the next steps with absolute paths.
It badges the Herdr tab `<base> ⏳N` with the number of counted items; `--tab` defaults to the
tab of `herdr pane current`, and `--base-label` overrides the label read with `herdr tab get`
(a badge left by a crashed watcher is stripped).

State lives in `<supervisor-dir>/.pending-state/`: `hash`, `pid`, `owner`, `tab`,
`base-label` and `notified/<Dn>`. `owner` is the Claude Code process that started the watcher;
when it is gone the watcher exits with `pending-watch: owner gone`, restoring the tab label. A
`pid` that no longer belongs to a pending-watch process is stale: `stop` never signals it and
`watch` replaces it. `stop` sends TERM, then KILL after 5 s.

`line` prints e.g. `⏳ 2 đang chờ bạn (D1, D3 mới) → /Users/me/supervisor/atoria--atoria-sup.md`;
"mới" marks an item that has not been notified yet, and `(watcher off)` is appended when no
watcher is running.

## Notifications

For a new item, a reminder (every `PENDING_RENOTIFY_SECONDS`, default 1800) and a malformed
header, the watcher sends a Herdr notification (`herdr notification show`). A Herdr
notification cannot carry a click action, so when `terminal-notifier` is on `PATH` the watcher
also sends a desktop notification with the same title and body. Its subtitle names the ledger
file, the last line of its message gives its full path, and clicking it opens that file. A
reminder replaces the earlier desktop notification of the same item. Without
`terminal-notifier` only the Herdr notification is sent, and on macOS the watcher says so once
when it starts (`pending-watch: terminal-notifier not found …`). When `terminal-notifier`
fails, most often because macOS has notifications switched off for it (System Settings →
Notifications → terminal-notifier), the watcher prints `pending-watch: terminal-notifier
failed …` once and keeps running.
