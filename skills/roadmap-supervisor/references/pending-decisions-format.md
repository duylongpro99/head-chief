# Pending-decisions ledger

Every question to the operator goes into the ledger first. A dialog can be cancelled and
queues every other event while open, a chat question scrolls away, compaction drops both; the
ledger keeps it. The dialog is only a shortcut.

## Files

- Live ledger: `~/supervisor/<project>--<session>.md` (`SUPERVISOR_HOME` overrides the folder).
  `<dir>/ledger.path` names it; every command reads it through that file. It holds only OPEN
  items, and the operator edits it by hand.
- `<dir>/pending-decisions.archive.md`: recorded items, ANSWERED, oldest first.
- `<dir>/pending-decisions.final.md`: the ledger after `close`, with the items still OPEN.

Write the ledger only through `add`, `record` and `seen`, never with Edit, Write or a redirect into the file (to add, write the item to a file with the Write tool and pass it to `add --file`);
the one exception is a `Conflict:` line (below). Read it only through `answers` and `list`.

## Item

An item is `## D<n> · <scope> · OPEN · <YYYY-MM-DD HH:MM>`, the question on one line, the
options (recommended first, real numbers, in the operator's language), `Chặn:` (what waits on
it), `Seen: [ ]` and `Answer:`. Give `add --file` a file with the scope line, the question,
the options and `Chặn:`; it writes the rest and prints the new `D<n>`. Example:

```text
## D3 · M5 · OPEN · 2026-11-17 11:40
Câu hỏi: Judge model cho visual check?
- A (đề xuất): flash — 40–90 s/lần
- B: qwen3.8-max — 227–811 s/lần
Chặn: M5-cook
Seen: [ ]
Answer:
```

`list` shows each OPEN item as **unseen** (counted in the tab badge and footer, reminded),
**seen** (`Seen: [x]`: answer later; not counted or reminded, still OPEN and in the final
report) or **answered** (the operator wrote after `Answer:`; record it).

## How the operator answers

1. In chat: `D3: A` (any text after the colon) or `D3 seen`. A dialog answer counts as chat;
   a worker's message never counts, even when it quotes the operator.
2. In the file: text after `Answer:`, or `Seen: [x]`, then save. The watcher exits with
   `pending-watch: user-edit`, which wakes you.

## Recording

`record <dir> D<n> <dialog|chat|file> [text]`: for `dialog` and `chat` pass the operator's
words verbatim; for `file` pass no text (the item's answer is used, every line). It stamps
`Answer: 2026-11-17 12:05 (chat) A`, moves the item to the archive and stores the hash. For
chat `D<n> seen`, run `seen <dir> D<n>`; a `Seen: [x]` set in the file needs no write.

**Conflict.** When two channels give different answers for one item, record neither: write
both, verbatim with time and channel, on a `Conflict:` line above `Seen:`, keep `Answer:`
empty, run `synced` in the same Bash call, and ask the operator in chat to confirm one.

## Commands

```bash
W=<skill-dir>/scripts/pending-watch.sh
$W init    <dir> --session <name>  # prints the ledger path; another folder's file: new --session
$W watch   <dir>              # run_in_background; refuses a second watcher for the folder
$W add     <dir> --file <dir>/questions/<topic>.txt   # prints D<n>; the file is written with
                              # the Write tool: scope line, question, options, Chặn:
$W record  <dir> D3 chat 'A'  # or: dialog '<text>', or: file
$W seen    <dir> D3
$W answers <dir>              # full block of each OPEN item with an answer
$W list    <dir>              # D<n> · <scope> · unseen|seen|answered · <question>
$W line    <dir>              # footer; end every turn with it while it prints anything
$W synced  <dir>              # after a Conflict: line; before restarting watch after user-edit
$W close   <dir>              # stops the watcher, moves the ledger to pending-decisions.final.md
$W stop    <dir>              # stops the watcher, restores the tab label
```

## What to do next

- **`watch` exits with `user-edit`**: follow the steps it prints: `answers`, `record ... file`
  each answer, `synced` even when you recorded nothing (or the new watcher exits again on the
  same edit), then `watch` again with `run_in_background`.
- **`add` warns that no watcher is running**: the item gets no badge or notification and a
  file answer wakes nobody. Start the command it prints, with `run_in_background`, now.
- **`line` ends with `(watcher off)`**: no watcher is running. Start `watch` with
  `run_in_background`, then print the footer.
- **`watch` prints `terminal-notifier failed …`**: macOS has notifications switched off for
  it. Tell the operator once (System Settings → Notifications → terminal-notifier); the
  watcher keeps running with Herdr notifications only.
- **A recorded item is back in `list`, or an item you added is gone**: the operator's editor
  saved an old buffer over the file. A returned item with a file answer: `record ... file`
  again. A returned `dialog` or `chat` item: record it again with the channel and text from
  the archive. An item that disappeared: `add` it again.
- **`D<n> has an answer in the file that is not recorded yet`** (stderr of `add`, `record`,
  `seen`, `synced`): record it now; the watcher will not report it again.
- **Exit 3** (`ledger changed; run answers again`): the operator saved meanwhile and nothing
  was written. Run `answers`, record what it shows, then retry.
- **Exit 2** (`malformed header '...'`) from `answers`, `list` or `line`: show the operator
  that line and ask them to fix it in the file; their save ends the watcher as a `user-edit`.
- **Exit 1** from `record`: unknown or non-OPEN `D<n>` (check `list`), a `file` record with no
  answer in the file, or an answer that differs from one in the file or the archive: a conflict.

Changing the script? See `docs/pending-watch-internals.md` in the head-chief repository (not shipped with an installed copy of the skill).
