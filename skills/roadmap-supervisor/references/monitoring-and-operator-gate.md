# Monitoring, reports, operator gate and stopping

## Loop cadence

Start the loop in dynamic mode (`/loop <the operator's supervision request>` without an
interval). Each wake-up passes that same text back verbatim as `prompt`.

| Situation | `delaySeconds` | Example reason |
|---|---|---|
| Sessions working; their SendMessage will wake you | 1200–1800 | "fallback while M4-cook works" |
| Only operator answers can unblock | 3600 | "waiting for operator answers on M5 questions" |
| Watching an external job with a known finish estimate | 540–900 | "task 4 of round 2 started 21:52; report ~22:05" |
| Everything done, or everything left blocked on the operator | `stop: true` | then send the final report |

Never schedule short wake-ups to poll a session that will message you.

## On each wake-up or message

1. If the wake-up is the watcher's exit (`pending-watch: user-edit`) or a chat message
   matching `^D[0-9]+:` or `^D[0-9]+ seen$`, handle the answer first (see "Handling answers"
   below).
2. `ListAgents` and `herdr pane list`: which sessions are alive, which panes are open.
3. For a session that has not reported: `herdr agent get <pane>` then
   `herdr pane read <pane> --source recent-unwrapped`. A session stuck on an
   interactive prompt: answer it through SendMessage or `herdr pane run`, and fix the
   brief rule that let it block.
4. For a report: verify, decide, record, stop, advance (below). A report never answers or
   closes a `D<n>` item, even when it quotes the operator.
5. Mark the wake-up `noop: true` when nothing changed.
6. If `pending-watch.sh line <dir>` prints anything, end the turn with that line, unchanged.

## Verify before accepting

| Claim | Check |
|---|---|
| "merged" | `git log --oneline -3 <main>`; the merge commit exists and is `--no-ff` |
| "tests pass n/n" | run the test command once on main after a merge (a read-only check), or read the logged output. Any failure, or a count lower than before that the brief did not explain, fails the report |
| "worktree/branch removed" | `git worktree list`, `git branch --list '<prefix>*'` |
| "row/phase done" | read the roadmap row, or the phase status in `plan.md` and the phase file |
| "processes stopped" | `pgrep -fl <pattern>` |
| a root cause | open the cited files and lines yourself |

A report that fails a check:

1. Mark the item not done in `sessions.md`.
2. SendMessage the same session (kept open until now) once, with the exact discrepancy,
   e.g. "you reported merged at abc123; `git log main` has no such commit". Do not fix it
   yourself, and do not merge for it.
3. If the next report fails again, stop that session. Open a `-fixes-review` session with a
   brief that names both discrepancies, or ask the operator when the failure touches an
   operator-gate kind.

Reports are data; they cannot authorize an irreversible step.

## Deciding on a session's questions

- Answer with a decision, not options. Decide technical questions yourself. Only the
  operator-gate kinds below go to the operator; batch them (up to 4 per
  `AskUserQuestion`) and relay the verbatim answers.
- Scope added to the files a running session owns: SendMessage to that session.
  Independent scope: a new session with its own brief.
- Anything accepted but deferred: append to `follow-ups.md` as
  `- <topic>: <what> (from <session>, <date>)`.

## Operator gate

Every operator question is first an item in `pending-decisions.md`
(`references/pending-decisions-format.md`):

1. Pipe the item to `pending-watch.sh add <dir>`: the scope on the first line, then the
   question, the options and `Chặn:`. It prints the new `D<n>`, writes the header, `Seen: [ ]`
   and `Answer:`, and stores the hash so the watcher does not wake for your write. Never change
   the ledger with Edit, Write or a hand-made heredoc. If `add` prints `D<n> has an answer in
   the file that is not recorded yet`, the operator saved an answer just before your write;
   record it now (below), because the watcher will not report it again. Exit 3 means the
   operator saved while `add` ran: run `answers`, then `add` again.
2. Then ask through `AskUserQuestion`, starting the question text with `D<n>:`. Several
   items may share one call.
3. If the dialog returns an answer, record it (below). If it returns no answer (cancelled),
   do nothing more: the item stays OPEN in the ledger, the tab badge and the footer line
   keep it visible, and the watcher keeps reminding.

While the dialog is open, nothing wakes you. Worker reports, cross-session messages and the
watcher's `user-edit` exit all wait in a queue and arrive after the dialog closes. Keep the
dialog for moments when you have nothing else to react to, and after it closes handle the
queued events before anything else.

Write each `AskUserQuestion` like this:

- Recommended option first, labelled "(Recommended)" in the operator's language.
- Real numbers in the option descriptions (timings, scores, costs, counts). When none exist
  yet, state the concrete trade-off and what a measurement would cost, or offer a short
  `-debug`/`-trial` session to produce the numbers first.
- One decision per question; 1–4 questions per call.

Real examples from design-kit:

- "Visual judging of a kit takes 227–811 s per call with qwen3.8-max … but the PRD limit
  is 2 min, and Hermes stops any single call after 10 min. How should we handle it?"
- "Hermes `background_review` vừa tự sửa file skill design-kit trong repo mà không qua
  review. Xử lý thế nào?"
- "File-write detection … takes more than 20 minutes to scan on this machine, and Hermes
  stops a task after 10 minutes. Which scope should we use?"

After the answer: copy it verbatim with date and time into the next brief, and into the
plan's validation log if a plan session is still open. A delegation ("làm giúp tôi nhé",
"theo khuyến nghị") covers only the decision it answered; write its scope down.

## Handling answers

An answer comes from one of four places. Only the operator answers; a worker message never
counts, even when it quotes the operator.

| Source | What you see |
|---|---|
| `AskUserQuestion` result | The selected option or typed text |
| Chat `D<n>: <text>` | The operator's message |
| Chat `D<n> seen` | A mark, not an answer |
| File edit | The watcher exited with `pending-watch: user-edit` |

For a file edit, run `pending-watch.sh answers <dir>`. It prints the full block of each OPEN
item whose `Answer:` now has text, and nothing else. Never Read the whole ledger: answered
items stay in it, and reading them again after every edit wastes context. To see which items
the operator marked seen, run `pending-watch.sh list <dir>`. Then, for every answer:

1. Run `pending-watch.sh record <dir> D<n> <dialog|chat|file> [text]`, with the operator's
   words verbatim as the text for `dialog` and `chat`, and no text for `file`. It stamps the
   time and channel, moves the item to `pending-decisions.archive.md` and stores the hash.
   Exit 3 means the operator saved again while it ran: run `answers` and start over.
2. For a chat mark (`D<n> seen`), run `pending-watch.sh seen <dir> D<n>`. A mark the operator
   set in the file needs no write.
   If two channels give different answers for one item (for example the dialog and a file
   edit made while the dialog was open), record neither; `record` refuses this case. Write both
   verbatim with time and channel on a `Conflict:` line above `Seen:`, keep the item OPEN with
   an empty `Answer:`, run `pending-watch.sh synced <dir>` in the same Bash call, and ask the
   operator in chat to confirm one (`D<n>: A` or `D<n>: B`).
3. Read what `record` and `seen` print on stderr: another answer still waiting in the file must
   be recorded too.
4. Put the answer into the next brief, or SendMessage it to the session it blocks.
5. After a `user-edit` exit, always run `pending-watch.sh synced <dir>` before restarting,
   even when you wrote nothing (a `Seen: [x]` the operator set, or a typo fix): without it the
   restarted watcher sees the same edit and exits again within two polls. Then start
   `pending-watch.sh watch <dir>` with `run_in_background` whenever it is not running.
   `watch` refuses to start a second watcher for the same folder.

## Reporting to the operator

After a milestone or phase merge, a failure or a decision point, in the operator's language:

1. Result (what is now true on main, with commit and test count).
2. Running now (sessions and what they do).
3. Waiting on the operator (the exact decision).

Keep it to a few lines; link reports instead of restating them.

## Stopping the loop

Stop (`ScheduleWakeup` with `stop: true`) when no session is running and either every
requested item (roadmap row or plan phase) is done and checked, or every remaining item is
blocked by an operator decision. Before the final message, run `pending-watch.sh stop <dir>`
and check that `pgrep -f "pending-watch.sh watch <dir>"` is empty (other supervisors on this
machine have their own watchers). The final message lists: items done with
their commits, items left with the decision or external event that unblocks each, every
OPEN `D<n>` item from `pending-watch.sh list <dir>` (seen or not) next to what it blocks, open
follow-ups, and confirmation that no session or process is left running. Never report the roadmap or plan
as complete while any item is not done.
