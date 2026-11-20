# pending-decisions.md format

`<supervisor-dir>/pending-decisions.md` records every question the supervisor puts to the
operator. It exists because the other channels do not keep a question:
- an `AskUserQuestion` dialog can be cancelled, and while it is open, worker reports and the
  watcher's exit wait in a queue until it closes;
- a question asked as chat text scrolls away;
- compaction drops both.

The ledger is the record, and the dialog is only a shortcut. `scripts/pending-watch.sh`
reads the file and never writes it. Only the supervisor and the operator write it.

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

The file starts with one title line, `# Pending decisions`, followed by items in order of
`D<n>`. Never renumber or delete an item; `D<n>` codes are what the operator types.

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

Keep the operator's words verbatim. Add the time and the channel, then set the header to
ANSWERED:

```text
Answer: 2026-11-17 12:05 (chat) A
```

The channel is `chat`, `dialog` or `file`. An answer the operator wrote in the file is moved
into this form unchanged, with `(file)`.

## The four states

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

ANSWERED (recorded by the supervisor):

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
$W watch  <supervisor-dir>   # run_in_background; exits 0 with "user-edit" on an operator edit
$W synced <supervisor-dir>   # same Bash call as every supervisor write; lists unrecorded file answers
$W line   <supervisor-dir>   # footer, e.g. "⏳ 2 đang chờ bạn (D1, D3 mới) → /abs/pending-decisions.md"
$W stop   <supervisor-dir>   # TERM, then KILL after 5 s; restores the tab label
```

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
title and body. Its subtitle names the supervisor folder, the last line of its message gives
the full path, and clicking it opens that folder, where `pending-decisions.md` is. A reminder replaces the earlier desktop notification of the
same item. Without `terminal-notifier` only the Herdr notification is sent, and on macOS
the watcher says so once when it starts (`pending-watch: terminal-notifier not found …`). When
`terminal-notifier` fails, most often because macOS has notifications switched off for it
(System Settings → Notifications → terminal-notifier), the watcher prints
`pending-watch: terminal-notifier failed …` once and keeps running.
