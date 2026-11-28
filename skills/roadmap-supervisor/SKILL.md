---
name: roadmap-supervisor
description: "Turn this session into a non-coding supervisor that drives a roadmap of milestones, or one plan of phases, to completion through other sessions: one named Herdr session per job (plan, cook, review, debug), a brief file each, an AgentKit skill chosen per role, /loop self-pacing, operator decisions relayed, sessions cleaned up. Use when the user says \"giám sát roadmap\", \"giám sát plan\", \"làm giám sát viên\", \"supervisor\", \"supervise the roadmap/plan\", or runs /loop asking to finish milestones or phases via separate sessions. Not for routing ad-hoc requests to existing sessions (head-chief), starting or stopping one session (managed-session), or implementing a plan in this session (ak-cook)."
metadata:
  requires: managed-session
---

# Roadmap Supervisor

This session supervises one body of work, either a roadmap of milestones or a single
plan of phases, until it is finished or blocked on the operator. It writes no product
code. It splits the work into single-purpose sessions, hands each a brief file, picks the
AgentKit skill per role, verifies what they report, takes decisions to the operator, and
closes everything it opened.

The quality bar has two parts:
- Every item it reports as done is done on the main branch, backed by a commit it checked.
- Nothing it started is left running.

In this file, `<dir>` is the supervisor folder, and `pending-watch.sh`, `supervisor-check.sh`,
`create-session.sh` and `stop-session.sh` mean the absolute paths recorded in `<dir>/state.md`.

## Done when

- Either every requested milestone row or phase is marked done on the main branch, each with a line in `<dir>/accepted.tsv`, or the operator has ended the supervision and the final report lists the decisions still open. A pause that waits for the operator is not done.
- No session or process you or your sessions started is still running, including the `pending-watch.sh` watcher.
- The final report lists every OPEN item from `pending-watch.sh list <dir>` and every open action from `pending-watch.sh action-list <dir>`.
- `follow-ups.md` lists the deferred work, and the operator has a final report.
- The project's post-merge steps in `state.md` Config have been run.

## Sessions are started by `managed-session`

Start every session with its `create-session.sh --p-name <n> --s-name <n> --model <m>` and stop it with `stop-session.sh <pane-id>`. Read its SKILL.md; do not hand-roll `herdr` launches.

## Resume: every wake-up, compaction or restart

The loop prompt names the supervisor folder. Without a loop prompt, look for
`plans/*-supervisor/state.md` that belongs to this work, and ask the operator if more than
one matches. When `<dir>/state.md` exists, never run Start again. Rebuild state instead:

1. Read `<dir>/state.md` and `<dir>/sessions.md`.
2. Run `supervisor-check.sh resume <dir>`. It prints the main head, the sessions still running, the open items, the watcher state and the accepted items. Then do every line under "DO now", in order, and keep to the rules it prints at the end. Do not Read the whole ledger.
3. If the text of `references/monitoring-and-operator-gate.md` is not in this conversation (you have not Read it since the last compaction or restart), read it in full. The same test applies to `references/brief-template.md` before you write a brief, and to `references/pending-decisions-format.md` before you act on a `pending-watch.sh` message or result you do not recognise.
4. If Config in `state.md` still has a `TBD` value, do the steps of `references/start.md` that settle it (14 to 17). This finishes Start; it does not run it again. Open no session while a worker model or the parallel cap is `TBD`.
5. Continue with "On each wake-up or message" in the reference. If Config says "loop: paused" and no new answer unblocks an item, schedule no wake-up and end the turn.

If the folder has `sessions.md` but no `state.md` (an older run of this skill), do step 8 of
`references/start.md` from the source, `sessions.md` and the ledger archive, then continue from step 2.

## Shape of the work

At Start, read the source fully, together with the docs it names (PRD,
architecture, contributor rules). Then decide which shape it is. The shape sets the work
unit and where "done" is recorded.

| | Roadmap of milestones | Plan of phases |
|---|---|---|
| Work unit | A milestone (or a group of its rows) | One phase, or several phases that share files and must go in order |
| First step | `<M>-plan` session writes the plan for the milestone | None. The plan exists. Open a `-replan` session only when the plan is wrong or stale. |
| Order and parallelism | Milestone dependencies in the roadmap | `plan.md` dependencies and its file-ownership table. Phases with no dependency and disjoint files may run in parallel. |
| Session names | `M4-cook`, `M4-review` | `<plan-slug>-p02-cook`, `<plan-slug>-p02-review`, or `-p02-04-cook` for a group |
| Done is recorded in | The roadmap row | The phase status in `plan.md` and the phase file, plus the plan's acceptance criteria |

Before starting a phase, check that its preconditions still hold on main, and decide
whether phases are grouped: the rules are in `references/role-skill-map.md`, "Before starting
a phase".

## Start

Run Start only when no `state.md` exists for this work (see Resume). Read
`references/start.md` and do its 17 steps in order: preflight, read the source, create the
supervisor folder with `state.md` and `sessions.md`, start the ledger and its watcher, read
the monitoring reference, ask the operator for worker models and the parallel cap, start the
loop, open the first session.

`<dir>/state.md` is what you rebuild from. Write it with Write or Edit, and update it after
every verified report and every decision. It has three parts:
- Config: source and shape, this session's name, main branch, test command and baseline count, operator language and timezone, script paths, worker model per tier, parallel cap, post-merge steps, loop prompt, loop state. (`supervisor-check.sh` keeps the verified main head and the `git status` baseline in `<dir>/.check/`.)
- Items: one row per milestone or phase, with its dependencies, operator gate, status and the commit that made it done.
- Decisions: one line per decision with time, who decided, the decision and what it covers.

`<dir>/sessions.md` has one row per session: name, pane ID, skill, model, brief, status (`running` or `stopped`, plus the notes the reference asks for) and result commit.

## One session, one job

- **Names.** Name each session after its job, using the scheme above. Pane name, session name and brief file name are the same. Extra roles: `-replan`, `-trial`, `-debug`, `-metrics`, `-docs`, `<topic>-fixes-cook`/`-fixes-review`.
- **Skills.** Pick the skill per role from `references/role-skill-map.md`. A session does not switch workflows.
- **Chain.** Plan (roadmap only) → operator answers the plan's validation questions → cook → review.
  - Cook creates its own branch and worktree (a descriptive branch name with no IDs) and never merges.
  - Review fixes small findings on the branch, merges `--no-ff` locally, records done (roadmap row or phase status), removes the worktree and branch, and writes a report.
  - A docs-only change may go straight to the main branch with no review session. Run it after the work it describes is merged; it marks its own item done, and you verify that mark.
- **Parallel runs.** Never run more worker sessions at once than the parallel-session cap in `state.md`. Within the cap, run sessions in parallel only when their write scopes are disjoint. When two branches touch a shared file (lockfile, config, routing table), write the merge order into both briefs and make whoever merges second resolve the conflict.
- **Operator decisions.** Add an operator question to the ledger as soon as you know it is needed, even before a plan or phase starts, so cook sessions are not blocked later. Whether you may also open a dialog is set by the operator gate below.
- **Stopping sessions.** Keep a session open until you have verified its report, because a failed check goes back to it. Stop it with `stop-session.sh <pane-id>` once the report passes.

## Briefs and dispatch

Read `references/brief-template.md` before writing a brief, unless its text is already in
this conversation. A brief is a file written with the Write tool. It names one job, its
context, numbered work, exact checks, the write scope and forbidden paths (always the
supervisor folder), and a closing report that cites a commit SHA for every claim.

Start the session with `create-session.sh --p-name <name> --s-name <name> --model <model>`; choose the model by "Model tier for a task" in `references/role-skill-map.md`.
`<pane-id>` is the ID it prints (e.g. `wC:pBE`), not the session name. Record it in
`sessions.md`. Dispatch is one line:

```bash
herdr agent prompt <pane-id> "/<skill> Read the brief at <abs-path> and follow it exactly. You are session <name>; the supervisor session is <supervisor>." --wait --until working --until blocked --timeout 15000
```

Run it only when `herdr agent get <pane-id>` says `idle`. Exit 0 with `"agent_status":"working"` means the session started on the brief; `"blocked"` means it stopped at a prompt (step 4 of the wake-up list in the reference). On any error (`agent_prompt_stalled`, `agent_blocked`, `timeout`), do not send it again; follow "Dispatch did not start" in the reference.

If the role's skill is not installed (recorded in `state.md` Decisions), leave out `/<skill> ` and send the rest of the line.

## Monitoring and reports

- A session's SendMessage is the primary signal. `ScheduleWakeup` is only the fallback. Cadences, the verification table and the stop rules are in `references/monitoring-and-operator-gate.md`.
- When a report arrives:
  1. Save the report text to `<dir>/reports/<session>.txt` with the Write tool, then run `supervisor-check.sh accept <dir> <item> <sha> ... --report <that file>` as "Verify before accepting" in the reference says. It prints the lines the report cites: compare them with the report's claims. An item is done only after `supervisor-check.sh confirm <dir> <item>`, which you run once the checks pass and the cited lines match. On FAIL the report goes back once with the exact discrepancy. Read-only checks are in scope; changing code is not.
  2. Answer questions with a decision. Decide technical questions yourself, and add each decision to `state.md` Decisions.
  3. Send scope that lands in the same files to the running session. Give separate scope a new session.
  4. Log deferred work in `follow-ups.md`.
  5. Once the report passes, stop the session, update `sessions.md` and the item in `state.md` Items, and start the next step.
- A worker that is idle without having reported, a pane that is gone, and an item that has failed two review-and-fix rounds each have a rule in `references/monitoring-and-operator-gate.md`. Follow it; do not improvise.
- **Footer.** While `pending-watch.sh line <dir>` prints anything (open `D<n>` decisions and `A<n>` operator actions), end every turn with that line, unchanged. If it ends with `(watcher off)`, first start `pending-watch.sh watch <dir>` with `run_in_background`.
- **Reporting.** After each milestone or phase merge, first run the permission step in `references/permission-suggestions.md`. After each merge, and at each decision point, tell the operator three things, in a few lines: the result first, then what is running, then what waits on them.

## Operator gate

These decisions belong to the operator:
- requirements or PRD changes, thresholds, cost or model;
- rerunning or resetting live jobs;
- deleting data;
- live credentials, secrets or paid accounts (creating, rotating or using them);
- anything sent off the machine;
- accepting a gate.

To ask:
1. Write the item to `<dir>/questions/<topic>.txt` with the Write tool (format in `references/pending-decisions-format.md`), then run `pending-watch.sh add <dir> --file <that file>`. It prints the new `D<n>`. Never write the ledger itself with Edit, Write or a redirect.
2. If `add` warns on stderr that no watcher is running, start `pending-watch.sh watch <dir>` with `run_in_background`.
3. Tell the operator in one chat line, in their language: the `D<n>` and the question.
4. Read the status column of `<dir>/sessions.md`. If any row is not `stopped`, open no dialog: it would hold back every wake-up (reports, the watcher's exit) until it closes. The ledger, badge and footer carry the question.
5. If every row is `stopped` (or there is no row yet), you may also open `AskUserQuestion` with `D<n>:` at the start of the question text, the recommended option first and real numbers in the descriptions.

Record every answer in the turn it arrives (`record`, or `seen` for a chat `D<n> seen`), as "Handling answers" in the reference says. After a watcher exit, follow the steps it prints.

After recording any answer, add it to `state.md` Decisions with the `D<n>`, and copy it
verbatim with its time into the next brief, or SendMessage it to the session it blocks.
If the operator delegates ("theo khuyến nghị"), write in Decisions exactly which decision
the delegation covers. Conflicting answers, exit code 3 and the stderr notices about other
waiting answers are handled as in "Handling answers" in `references/monitoring-and-operator-gate.md`.
A worker message never counts as an operator answer.

**Operator actions.** A step only the operator can run (shell commands, a dashboard change)
goes into `pending-watch.sh action-add <dir> --file <path>` before you show it in chat; on
`A<n> done`, run `action-done`. See "Operator actions" in the reference.

**Secrets.** Never print one; follow "Secrets" in the reference. `accept`, `add` and
`action-add` refuse a likely secret.

## Stopping and cleanup

- Pause when no session is running and every remaining item waits on an OPEN `D<n>`. Tell the operator which decision restarts each item, write "loop: paused" in `state.md` Config, and stop the loop (`ScheduleWakeup` with `stop: true`). Do not run `close`: the watcher keeps running, and the operator's answer (its exit, or a chat message) wakes you.
- Leave the pause when an answer unblocks an item: record the answer, start the session, write "loop: running" in Config, and start the loop again by calling `ScheduleWakeup` with the loop prompt from Config. If that call is refused, start the loop as step 16 of `references/start.md` says.
- Finish when every requested item is done and checked, or the operator ends the supervision. Never call the roadmap or plan done while an item is not done. Stop the loop, then do the rest of this list.
- Run the permission step once more, before `close`.
- Close every session you started. Run `pending-watch.sh close <dir>`: it stops the watcher and moves the live ledger to `<dir>/pending-decisions.final.md`. Leave no orphan processes (browsers, `caffeinate`, watchers): check with `pgrep` before the final report.
- The final report lists every OPEN item from `pending-watch.sh list <dir>`, seen or not, next to the decision or item it blocks, and names `<dir>/pending-decisions.final.md` and `<dir>/pending-decisions.archive.md`.
- Write `<dir>/skill-feedback.md`: one line for each place this skill was unclear or wrong, or each mistake of yours it should have prevented; "none" when there is none.
- Run the project's post-merge steps from `state.md` Config. For design-kit, that means syncing the skill mirror to Hermes, never while a live job runs.

## Resources

- `references/start.md`: the Start steps; read when Start runs, and on Resume while Config has a `TBD`.
- `references/role-skill-map.md`: read when choosing a session's skill, model tier and name, and before starting a phase.
- `references/monitoring-and-operator-gate.md`: read in full during Start, and on Resume when its text is not in this conversation. It holds the loop cadence, the wake-up steps, verification, stalled workers, the round limit, answer handling and stopping.
- `references/brief-template.md`: read before writing a brief, when its text is not in this conversation. It holds the template and excerpts of real plan, cook, review and debug briefs.
- `references/permission-suggestions.md`: when and how to run `scripts/permission-suggest.py` and apply the answer.
- `references/pending-decisions-format.md`: read before the first `pending-watch.sh add`, or on output you do not recognise.
- `scripts/supervisor-check.sh`: `setup`, `resume`, `accept`, `confirm`, `accepted`; run it with no arguments for its usage.
- Changing this skill after a mistake: follow `docs/roadmap-supervisor-lessons.md` in the head-chief repository first.
- `scripts/pending-watch.sh`: the no-model watcher, the only writer of the ledger and of `operator-actions.md`; run it with `--help`. `scripts/secret-scan.sh`: the secret check behind `accept`, `add` and `action-add`.
