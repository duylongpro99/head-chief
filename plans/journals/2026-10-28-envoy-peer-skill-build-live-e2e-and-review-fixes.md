---
title: "envoy-peer skill: build, live E2E and review fixes"
date: 2026-10-28
summary: "Built the envoy-peer skill across 4 phases; live Herdr E2E proved 4 of 8 criteria fully, AC5/AC7 blocked by provider and login state; 10 review findings fixed; not committed."
---

# envoy-peer skill: build, live E2E and review fixes

## What happened

Executed `plans/261028-0731-envoy-peer-skill/plan.md` end to end. The new skill `skills/envoy-peer` dispatches a task to a peer CLI of a different kind (codex, grok, omp, agy, claude) in a Herdr pane, and has a reviewer check the result until ACCEPT or max rounds. Packaging added `install.sh`, an entry in `skills.sh.json`, README updates and 8 evals.

The live E2E in Herdr 0.8.0 surfaced three skill bugs, all fixed during the run. One example: `prompt-wait.sh` now says "nothing was sent; call again with the same --text" when the prompt never reached the pane. Onboarding was watched live. Codex's update and trust screens returned exit 4, the user answered them in the pane, and `start.sh` resumed in the same pane.

A high-level code review returned 10 findings, all real and all fixed:
- The reviewer guard ignored HEAD and the index, so a reviewer commit looked clean. It now snapshots `head`, `index_sha` and a manifest hash.
- `start.sh` could type the launch command into a program still running in a reused pane. It now requires the shell to own the foreground process group (Herdr `process-info`); otherwise it exits 4 "pane busy".
- `cleanup.sh` stopped at the first refused pane. It now attempts both roles.
- `terminal_id` is now read from the `pane split` output.
- A repo with no commits now gets a baseline note.
- The `run_bounded` watchdog no longer leaves orphan sleeps; it kills the whole process tree.
- `install.sh --uninstall` now works for a skill that has left the checkout.
- SKILL.md round and recovery wording was fixed (re-prompts within a round, `reviewing` status).

## Blocked by environment

- codex's configured provider (`aibox/glm-5.2`) was unreachable. No envoy kind could finish a task, so AC5 (the full FINDINGS → fix → ACCEPT loop) and AC7 (codex running the scripts itself) are not proven live.
- grok, omp and agy are not logged in, so the smoke-onboarding path for `no-probe` kinds was not rerun.
- codex auto-updated to 0.165.0 during the run. It left two detached `codex app-server` daemons (PIDs 70857, 70885, PPID 1). They were not killed because the skill did not start them directly.

## Decision

- Report status is DONE_WITH_CONCERNS rather than DONE. In plan.md, AC1, AC2, AC6 and AC8 are ticked. AC3, AC4, AC5 and AC7 each carry a note saying what was and was not proven.
- The secret grep still has 3 hits, all false positives ("Task-specific", plus the two `redact` regexes). The code was not changed to silence them.
- Nothing was committed: the plan leaves commits to the user.

## Next steps

- Fix codex's provider config or log in to grok/omp/agy, then rerun AC5 and AC7 live: a full loop to ACCEPT, and codex as the controller.
- After pushing, check `npx skills add duylongpro99/head-chief --skill envoy-peer`.
- Optionally kill the leftover codex daemons 70857 and 70885.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
