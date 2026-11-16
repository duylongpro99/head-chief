# Role → skill map

The supervisor picks the skill; the session runs only that workflow. The design-kit
column is evidence from that supervision (2026-11-11 → 11-14, 49 sessions), not a quota.

| Role (suffix) | Skill | Job | Writes | Design-kit sessions |
|---|---|---|---|---|
| `-plan`, `-replan` | `/ak-plan` | Plan a milestone, or repair a stale plan; put 3–8 validation questions with recommendations in the plan and SendMessage them to the supervisor | `plans/<dir>/` only | M2-plan, M2-replan, M5-plan, M6-plan |
| `-cook` | `/ak-cook` | Implement the named phases on a branch or worktree; never merge | Its branch, its report | M2-cook, M2-amend-cook (phases 00–02 of one plan), M5-verify-cook (15 in all) |
| `-trial`, `-metrics`, `-docs` | `/ak-cook` | A manual trial, a metrics report, or a docs-only change (may commit to main) | Reports, docs | M5-pipeline-trial, M6-metrics, M3M4-docs |
| `-review` | `/ak-code-review` | Review a branch, fix small findings on it, `merge --no-ff` locally, record done (roadmap row or phase status), delete worktree and branch, write a report | Branch, merge, done mark, report | M2-review … M5-watch-review (27 in all) |
| `-debug` | `/ak-debug` | Prove a root cause with evidence, propose the fix and a test that fails today; no product code | One debug report | judge-timeout-debug |
| operator-run (`-first-style`, `-landing-demo`) | `/ak-project-management` | Guide or observe a step the operator or an external agent performs, record evidence, close the item | Reports, status marks | M2-first-style, M2-landing-demo |

## Choosing

- Unknown cause of a failure: `-debug` first, then `-fixes-cook` from its report, then
  `-fixes-review`. A cook session sent to guess wastes a round.
- A review that finds something needing an operator decision reports it with a
  recommendation and does not merge.
- If another installed skill fits a job better (security audit, docs refresh), name it in
  the brief with the reason. Keep one skill per session.

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
