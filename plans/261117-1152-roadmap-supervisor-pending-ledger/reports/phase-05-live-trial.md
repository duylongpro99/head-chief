# Phase 5 live trial: pending-decisions ledger under Herdr

Date: 2026-11-17, 13:30–13:48 (Asia/Saigon). Branch `feat/roadmap-supervisor-pending-ledger`.

## Result

All seven steps ran. Six passed as written. Step 3's premise was wrong: a worker report
does **not** close an open `AskUserQuestion` dialog. Step 5 then confirmed that a watcher
exit does not wake the session while a dialog is open. Per the plan's stop condition, the
operator was asked and chose **(a) accept, fix the docs**. Commit `f4e07d3` does that and
adds a rule for answers that conflict, which the trial exposed.

## Setup and deviation

- Scratch repo under the session scratchpad, `.claude/` git-ignored, with both skills linked
  from the worktree. The supervisor session was `pw-trial-sup` (pane `wC:pF3`, tab `wC:tAX`
  labelled `pw-trial`).
- Deviation: lean trial, with no real worker sessions. The "worker report" in step 3 was sent
  from the controller session by SendMessage, the same channel a worker uses.

## Steps

| # | Step | Result | Evidence |
|---|---|---|---|
| 1 | Start: ledger created, watcher via `run_in_background` | PASS | Watcher PID 59461 recorded in `sessions.md` |
| 2 | Raise D1 with a dialog | PASS | The tab showed `pw-trial ⏳1` and `notified/D1` was written. The notification was attempted; it was not checked visually. |
| 3 | A worker report arrives while the dialog is open | Premise FALSE | The report was queued at 13:34:45; the dialog stayed open until the operator chose "B: Change it" at 13:35:24; the report was delivered afterwards. The supervisor recorded `(dialog) B: Change it`, rejected the fake report (commit and branch absent, HEAD 651f368), and refused to count the report's quote of the answer. |
| 4 | Answer D2 in the file with no dialog open | PASS, 13 s | Edited 13:39:03; ANSWERED after 13 s as `(file) A, no changelog`; watcher restarted (65148). |
| 5 | Answer D3 in the file with a dialog open | Stop condition | The watcher exited 9 s after the edit; the session did not wake within 54 s. Operator chose (a). After Esc the queued exit was delivered. |
| 6 | Chat `D<n>: …` and `D<n> seen` | PASS | `D3: B. D4 seen` set D3 to ANSWERED `(chat) D3: B` and D4 to `Seen: [x]`; the tab went back to `pw-trial` and `line` printed nothing. |
| 7 | Stop the watcher, then clean up | PASS | `pgrep -f pending-watch` was empty and the label was restored. The session was stopped, `install.sh --uninstall --project` removed both links, and the scratch repo was deleted. |

## Findings

1. **The dialog blocks every wake-up.** Cross-session messages and `run_in_background`
   exits are queued until the dialog closes; they do not close it. The ledger still keeps
   the item visible (badge and footer), so nothing is lost, but nothing is processed while
   the dialog is open either. Fixed in the docs (option a).
2. **Conflicting answers.** With a dialog open, the operator chose B in the dialog while the
   harness had written A into the file. The supervisor, with no rule for this, recorded both
   on a `Conflict:` line, kept D3 OPEN and asked in chat. That behaviour is now the
   documented rule. The parser ignores the `Conflict:` line.
3. **Language.** The footer `line` text is Vietnamese even in an English session. This
   matches the operator's language and was left unchanged.
4. **Peer messages are not operator authority.** The supervisor correctly refused the
   harness's claim that an Esc came from a test harness, and refused worker quotes as
   answers.

## Verification after the fix

`scripts/tests/test-pending-watch.sh` reports 7/7 passed.
