# Role → skill map

The supervisor picks the skill; the session runs only that workflow. The design-kit
column is evidence from that supervision (2026-11-11 → 11-14, 49 sessions), not a quota.
The base tier column is where a role starts: "strongest" is the strongest model the
operator allows, "default" is the operator's default model, "cheaper" is a cheaper model
the operator allows. "Model tier for a task" below moves it up or down for one task.

| Role (suffix) | Skill | Job | Writes | Base tier | Design-kit sessions |
|---|---|---|---|---|---|
| `-plan`, `-replan` | `/ak-plan` | Plan a milestone, or repair a stale plan; put 3–8 validation questions with recommendations in the plan and SendMessage them to the supervisor | `plans/<dir>/` only | strongest | M2-plan, M2-replan, M5-plan, M6-plan |
| `-cook` | `/ak-cook` | Implement the named phases on a branch or worktree; never merge | Its branch, its report | default | M2-cook, M2-amend-cook (phases 00–02 of one plan), M5-verify-cook (15 in all) |
| `-trial`, `-metrics`, `-docs` | `/ak-cook` | A manual trial, a metrics report, or a docs-only change (may commit to main) | Reports, docs | cheaper | M5-pipeline-trial, M6-metrics, M3M4-docs |
| `-review` | `/ak-code-review` | Review a branch, fix small findings on it, `merge --no-ff` locally, record done (roadmap row or phase status), delete worktree and branch, write a report | Branch, merge, done mark, report | strongest | M2-review … M5-watch-review (27 in all) |
| `-debug` | `/ak-debug` | Prove a root cause with evidence, propose the fix and a test that fails today; no product code | One debug report | strongest | judge-timeout-debug |
| operator-run (`-first-style`, `-landing-demo`) | `/ak-project-management` | Guide or observe a step the operator or an external agent performs, record evidence, close the item | Reports, status marks | default | M2-first-style, M2-landing-demo |

## Choosing

- Unknown cause of a failure: `-debug` first, then `-fixes-cook` from its report, then
  `-fixes-review`. A cook session sent to guess wastes a round.
- A review that finds something needing an operator decision reports it with a
  recommendation and does not merge.
- If another installed skill fits a job better (security audit, docs refresh), name it in
  the brief with the reason. Keep one skill per session.
- Model: see "Model tier for a task" below.

## Model tier for a task

The operator confirms one model per tier at Start (Config in `state.md`: "worker models:
strongest=…, default=…, cheaper=…"; two tiers may share a model). You choose the tier for
each session; you never use a model that is not in Config. To add or change a model, ask
through the operator gate.

Choose the tier when you write the brief, in this order:

1. Take the role's base tier from the table above.
2. Raise it one tier when any of these is true for the task:
   - it changes a contract other items depend on: a schema, a migration, a public API, a
     shared config format;
   - it touches concurrency, security, money, or deletion of data;
   - it edits more than three modules, or the plan marks it high risk;
   - the plan gives the goal but not the steps, so the session must design;
   - an earlier round of the same item failed `accept` or was sent back by review.
3. Lower it one tier only when all of these are true:
   - the change is mechanical: docs, a rename, a config value, a move, generated output;
   - the plan or brief gives the exact steps and the files;
   - an existing test or command shows a wrong result.
4. `-plan`, `-replan` and `-debug` stay on the strongest tier. A `-review` session uses
   the tier of the cook session it reviews, or a higher one, never a lower one.
5. If you cannot tell, keep the base tier. If rules 2 and 3 both seem to apply, rule 2 wins.

Record the choice in the model cell of the session's row in `sessions.md`, with the tier
and the reason: `opus (strongest: changes the billing schema)`. Start the session with
that model: `create-session.sh --model <model>`.

When a second round at the same tier also fails, start the next round one tier up. If the
tier is already the strongest, stop and ask through the operator gate: the brief or the
plan is the likely problem, not the model.

## Naming

| Work | Pattern | Example |
|---|---|---|
| Roadmap milestone | `<milestone>-<role>` | `M4-schema-review` |
| Plan phase | `<plan-slug>-p<NN>-<role>` | `billing-p02-cook` |
| Group of phases | `<plan-slug>-p<NN>-<NN>-<role>` | `billing-p02-04-cook` |
| Cross-cutting fix | `<topic>-<role>` | `verify-fixes-cook`, `cleanup-review` |
| Second round | add `-2` | `M2-review-2` |

Use the same string for `--p-name`, `--s-name` and the brief file name, so a pane, a
message sender and a brief match at a glance.

## Before starting a phase

Before starting a phase, check that its preconditions hold on the current main branch.
Plans go stale: a file may have moved, or an earlier phase may have changed a contract.
Check that the paths, commands and contracts the phase file names still exist (`git ls-files`,
`git grep`). If they do not hold, run one `-replan` session before any cook session. Scope it
to the stale phases and every phase that depends on them. It edits only the plan directory,
commits straight to the main branch like a docs change, and you verify its diff before the
cook starts.

For a plan of phases, you own the plan's open validation questions. Relay them to the
operator yourself, and have the replan session (if any) record the answers in the plan.

Group phases into one session only when they edit the same files or each one is too small
to review alone. Otherwise run one session per phase. When two parallel phases consume a
contract from the same earlier phase, start them only after that phase is merged.
