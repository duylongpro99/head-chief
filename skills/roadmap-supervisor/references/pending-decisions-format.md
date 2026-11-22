# Pending-decisions ledger format

The ledger records every question the supervisor puts to the operator. It exists because the other channels do not keep a question:
- an `AskUserQuestion` dialog can be cancelled, and while it is open, worker reports and the
  watcher's exit wait in a queue until it closes;
- a question asked as chat text scrolls away;
- compaction drops both.

The ledger is the record, and the dialog is only a shortcut. The operator edits it by hand.

## Where the files are

| File | Where | What |
|---|---|---|
| Live ledger | `~/supervisor/<project>--<session>.md` (`SUPERVISOR_HOME` overrides the folder) | OPEN items of one running supervisor. The operator answers every project here. |
| `ledger.path` | `<supervisor-dir>/` | One line: the absolute path of the live ledger. Every command reads the ledger through it. |
| Archive | `<supervisor-dir>/pending-decisions.archive.md` | Recorded items, ANSWERED, oldest first |
| Final ledger | `<supervisor-dir>/pending-decisions.final.md` | The live ledger after `close`; items still OPEN when the supervisor stopped |
| Old layout | `<supervisor-dir>/pending-decisions.md` | Used when `ledger.path` is missing. `init` migrates it and keeps it as `pending-decisions.md.migrated`. |

`init <supervisor-dir> --session <name>` creates the live ledger with this header (the project
is the git root of `<supervisor-dir>`, or outside git the nearest folder above it that holds
`.claude`; `--project`, `--tab` and `--pane` override the defaults, which come from that
folder's name and `herdr pane current`):

```text
# Pending decisions
Project: atoria · /Users/me/personal/agent/atoria
Supervisor: atoria-sup · Herdr tab w1:t3 · pane w1:p7
Folder: /Users/me/personal/agent/atoria/plans/261122-1000-x-supervisor
Started: 2026-11-22 10:05 · Archive: /Users/me/personal/agent/atoria/plans/261122-1000-x-supervisor/pending-decisions.archive.md
```

No header line starts with `## `, so the parser skips it. `init` reuses an existing file whose
`Project:` and `Folder:` are this project and this supervisor folder (a rebuild after
compaction), and refuses one that belongs to another project or folder: give a second
supervisor in the same repo its own `--session`. It migrates an old in-project
`pending-decisions.md`, and the final ledger of a supervisor started again after `close`: it
stops the watcher, appends ANSWERED items to the archive, copies OPEN items unchanged and in
order into the live ledger, and renames the old file to `<name>.migrated` last. OPEN items keep
their numbers, and `add` numbers past every ledger, archive and final file, so no `D<n>` is
reused. A rerun after a crash copies no item twice. An operator save during the migration
makes it exit 3 with nothing written.

`close <supervisor-dir>` stops the watcher, moves the live ledger to
`pending-decisions.final.md` (with a time suffix when that name is taken) and points
`ledger.path` at it, so `list` and `line` still work. `~/supervisor` then holds only the
ledgers of running supervisors.

## Who writes it

The supervisor changes it only through `scripts/pending-watch.sh add`, `record` and `seen`,
never with Edit, Write or a hand-made heredoc. The one exception is a `Conflict:` line (below),
written from Bash with `pending-watch.sh synced <dir>` in the same call.

## Item template

```text
## D<n> · <item it blocks or belongs to> · OPEN · <YYYY-MM-DD HH:MM>
<the question, on one line, in the operator's language>
- A (<recommended, in the operator's language>): <option with real numbers>
- B: <option>
Chặn: <sessions or phases waiting on it>
Seen: [ ]
Answer:
```

Real example:

```text
## D3 · M5 · OPEN · 2026-11-17 11:40
Câu hỏi: Judge model cho visual check?
- A (đề xuất): flash — 40–90 s/lần
- B: qwen3.8-max — 227–811 s/lần
Chặn: M5-cook
Seen: [ ]
Answer:
```

The file starts with the header above, followed by items in order of `D<n>`. `add` writes the header, `Seen: [ ]` and `Answer:`; you pipe it the scope on the first
line and the question, options and `Chặn:` below it. Once an answer is recorded, `record`
moves the item to the archive, so the live file holds only OPEN items. Numbers are never reused: `add` numbers past the highest `D<n>` in the live
file and the archive, because `D<n>` codes are what the operator types.

## Fields

| Field | Meaning | Parser rule |
|---|---|---|
| Header | Code, scope, status, time the question was raised | Must match `^## D[0-9]+ · <scope> · (OPEN\|ANSWERED) · YYYY-MM-DD HH:MM$`, with ` · ` (space, middle dot U+00B7, space) between fields. Any other line starting with `## D` is malformed: the watcher notifies an error and `line` exits 2. |
| First non-empty line | The question | Used as the notification body. Its label (`Câu hỏi:`, `Question:`) is free. |
| Option and `Chặn:` lines | Options with the recommendation first, and what waits | Free text, in the operator's language |
| `Seen: [ ]` / `Seen: [x]` | The operator has read the question and will answer later | `[x]` or `[X]` stops reminders and removes the item from the tab badge and the footer line. The item stays OPEN. |
| `Answer:` | The operator's answer | Empty means unanswered. Text after `Answer:`, or any non-blank line after it before the next `## ` line, counts as an answer. |

An item is:
- **open** when its header says OPEN and `Answer:` is empty;
- **counted** (badge, footer, reminders) when it is open and `Seen: [ ]`;
- **answered but unprocessed** when its header says OPEN and `Answer:` has text. The operator
  wrote it in the file; the supervisor has not recorded it yet.

## Two ways to answer

1. **In chat**: `D3: A` (any text after the colon), or `D3 seen` to mark it seen. The
   supervisor writes the answer or the mark into the file.
2. **In the file**: write after `Answer:`, or change `Seen: [ ]` to `Seen: [x]`, and save.
   The watcher sees an edit that the supervisor did not sync, waits one more poll so a
   half-saved file is not read, and exits with `pending-watch: user-edit`. That exit wakes
   the supervisor.

An `AskUserQuestion` answer is the same as a chat answer. A worker's message is never an
operator answer, even when it quotes one. When two channels give different answers for one
item, the supervisor records neither: it writes both on a `Conflict:` line above `Seen:`,
keeps the item OPEN and asks the operator to confirm one in chat. The parser ignores the
`Conflict:` line.

## How the supervisor records an answer

Run `pending-watch.sh record <dir> D<n> <dialog|chat|file> [text]`. For `dialog` and `chat`,
pass the operator's words verbatim as the text. For `file`, pass no text: the answer already
in the item is used unchanged, every line of it. `record` stamps the time and the channel,
sets the header to ANSWERED, appends the item to `pending-decisions.archive.md` (created with
the title `# Answered decisions`), removes it from the live file and stores the new hash:

```text
Answer: 2026-11-17 12:05 (chat) A
```

`record` refuses (exit 1) an unknown `D<n>`, an item that is not OPEN, a `file` record with no
answer in the file, and a `dialog` or `chat` answer that differs from one already written in
the file. That last case is a conflict: write the `Conflict:` line instead. An item whose
`Answer:` line was deleted still gets one in the archive.

The archive is written before the live file is replaced. A crash in between, or an operator
save that lands after the archive write, leaves the item in both files. Running the same
`record` again removes it from the live file and does not copy it twice, as long as the
archive copy holds the same answer. When the operator has changed the answer since, `record`
refuses (exit 1) and changes nothing: write both answers on a `Conflict:` line.

An editor that still holds the old file in an unsaved buffer can save it over the new one. That
brings back recorded items and removes items added since. A brought-back item with a file
answer shows up in `answers`, and `record ... file` removes it again. A brought-back `dialog`
or `chat` item has an empty `Answer:`, so the operator is asked again; record the answer from
the archive with the same channel and text. Re-add any item that disappeared, with `add`.

## The four states

The first three live in the ledger. ANSWERED appears only in the archive.

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

OPEN and seen (not counted, still listed in the final report):

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

ANSWERED (recorded by `record`, in `pending-decisions.archive.md`):

```text
## D3 · M5 · ANSWERED · 2026-11-17 11:40
Câu hỏi: Judge model cho visual check?
- A (đề xuất): flash — 40–90 s/lần
- B: qwen3.8-max — 227–811 s/lần
Chặn: M5-cook
Seen: [ ]
Answer: 2026-11-17 11:52 (file) A, nhưng ghi số đo vào report
```

## Watcher commands

```bash
W=<skill-dir>/scripts/pending-watch.sh
$W init   <supervisor-dir> --session <name>   # prints the live ledger path; migrates an old ledger
$W close  <supervisor-dir>   # stop the watcher, move the ledger to pending-decisions.final.md
$W watch  <supervisor-dir>   # run_in_background; exits 0 with "user-edit" on an operator edit
$W add    <supervisor-dir> <<'EOF'   # prints the new D<n>
M5
Câu hỏi: Judge model cho visual check?
- A (đề xuất): flash — 40–90 s/lần
- B: qwen3.8-max — 227–811 s/lần
Chặn: M5-cook
EOF
$W record <supervisor-dir> D3 chat 'A'   # or: dialog '<text>', or: file (answer already in the item)
$W seen   <supervisor-dir> D3            # chat "D3 seen"
$W synced <supervisor-dir>   # accept the file as is: after a hand-written Conflict: line (same Bash
                             # call), or before restarting the watcher after a user-edit exit
$W answers <supervisor-dir>  # full block of each OPEN item with an answer; nothing when none
$W list   <supervisor-dir>   # one line per OPEN item: D<n> · <scope> · unseen|seen|answered · <question>
$W line   <supervisor-dir>   # footer, e.g. "⏳ 2 đang chờ bạn (D1, D3 mới) → /Users/me/supervisor/atoria--atoria-sup.md"
$W stop   <supervisor-dir>   # TERM, then KILL after 5 s; restores the tab label
```

`add`, `record` and `seen` build the new file from a snapshot and replace the ledger only
when it has not changed since. The check and the replace are two steps, so a save in the same
instant can still be overwritten; the window is a few milliseconds. If the operator saved in
between, they write nothing to the ledger, exit 3
and print `pending-watch: ledger changed; run answers again`: run `answers`, then retry. Each
one stores the new hash, so the watcher does not wake for it, and prints on stderr any other
answer still waiting in the file (`D<n> has an answer in the file that is not recorded yet`);
record those too, because the watcher will not report them again.

`answers` and `list` write nothing and exit 2 on a malformed header, like `line`. `answers`
prints each block from its `## D` line up to the next `## ` line, without trailing blank
lines, with one blank line between blocks. Use them instead of reading the file: after a
`user-edit` exit run `answers`, and for the final report or a rebuild after compaction run
`list`.

State lives in `<supervisor-dir>/.pending-state/` (`hash`, `pid`, `owner`, `tab`,
`base-label`, `notified/<Dn>`). `owner` is the Claude Code process that started the watcher;
when it is gone the watcher exits with `pending-watch: owner gone`, restoring the tab label. `PENDING_POLL_SECONDS` (default 5) and `PENDING_RENOTIFY_SECONDS`
(default 1800) override the timings. `line` appends `(watcher off)` when no watcher is
running; "mới" marks an item that has not been notified yet. A `pid` that no longer belongs
to a pending-watch process is treated as stale: `stop` never signals it and `watch` replaces
it. CRLF line endings are accepted.

## Notifications

For a new item, a reminder and a malformed header, the watcher sends a Herdr notification
(`herdr notification show`). A Herdr notification cannot carry a click action, so when
`terminal-notifier` is on `PATH` the watcher also sends a desktop notification with the same
title and body. Its subtitle names the ledger file, the last line of its message gives
its full path, and clicking it opens that file. A reminder replaces the earlier desktop notification of the
same item. Without `terminal-notifier` only the Herdr notification is sent, and on macOS
the watcher says so once when it starts (`pending-watch: terminal-notifier not found …`). When
`terminal-notifier` fails, most often because macOS has notifications switched off for it
(System Settings → Notifications → terminal-notifier), the watcher prints
`pending-watch: terminal-notifier failed …` once and keeps running.
