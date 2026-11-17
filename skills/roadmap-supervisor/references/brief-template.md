# Brief template

Write the brief with the Write tool or a quoted heredoc (`<<'EOF'`), into the durable
`briefs/` folder, then grep it for the commands it must contain before dispatching.
Fill every `<…>`; delete a section only when it truly does not apply.

```markdown
# Brief: <session-name>

You are session "<session-name>". Your only job: <one sentence: what, with which skill,
and the hard boundary, e.g. "you do NOT merge" / "diagnosis only, write no product code">.
The supervisor is session "<supervisor-name>". <Name the downstream session if any, e.g.
"<m>-review will review your branch and merge it.">

Context
- Working dir: <abs path>. Timezone: <tz>. Reports in <language>.
- Read fully: <plan.md and phase files>, <docs sections>, <prior reports>.
- State: main is at <sha>; <test command> passes <n>/<n>. <What just happened.>
- Operator decisions: "<verbatim answer>" (<date time>). <Scope of any delegation.>
- Running in parallel: <session> on <branch/files>. Do not touch those files. <Merge
  order and who resolves the shared-file conflict.>

Work
1. <Step, with branch and worktree path when it changes code.>
2. <Step.> Each fix is its own commit, with a test that fails before the fix.
3. <Explicitly out of scope: phases or items not to start.>

Checks
- <Exact test command, env vars, runtime versions.>
- <Project-specific check, e.g. grep for IDs in new files and commit messages.>
- A flaky test: rerun it alone and report it; do not edit the test to pass.

Rules
- Write scope: <paths>. Do not touch: <paths, live data, user config, external accounts>.
- Conventional commits ending with: <the attribution line your own session was given>. No plan, phase, milestone or gate IDs in
  code, comments, test names, commits or branch names. `git add` explicit paths only.
- <Merge rules for review: fix small findings on the branch; `git merge --no-ff`
  locally; mark the roadmap row or the phase status in plan.md done; remove the worktree
  and branch.>
- No GitHub unless stated. Stop every process you start (<pgrep check>).
- Do not wait on interactive questions. Send them to <supervisor-name> with SendMessage,
  with your recommendation, and keep working on anything not blocked.
- Write your report to <plans/reports/<type>-<date>-<slug>.md> in <language>.

When done, send <supervisor-name> (SendMessage): <what to include: branches and heads,
the merge or commit SHA behind every claim, tests and counts, findings and fixes, the
report path, what still needs the operator>; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
```

Dispatch:

```bash
herdr pane run <pane> "/<skill> Read the brief at <abs-path> and follow it exactly. You are session <name>; the supervisor session is <supervisor>."
# a few seconds later (it may still say idle right after the run):
herdr agent get <pane>
```

## Real briefs this template was checked against

Excerpts from the design-kit supervision. Each shows a role-specific part of the template.

### Plan (M2-plan, `/ak-plan`)

> You are session "M2-plan". Your only job is this plan. … Do not start other sessions or
> subagent workers for implementation.
>
> Facts the plan must handle
> 2. DK-202 … depends on two operator inputs … Plan an explicit operator checkpoint for
>    these, with a concrete template or checklist the operator can fill in.
> 3. The audit colour threshold margin is thin. good.html scores 0.9774 and bad.html
>    0.9718, against 0.95. … The supervisor's recommendation is to check first whether a
>    correct page should style form controls with tokens, before lowering any threshold.
>
> Operator questions — Do NOT block waiting for an interactive answer. Put 3–8 validation
> questions with your recommended answer in the plan. Send them to the supervisor with
> SendMessage. When the supervisor replies with the operator's answers, record them in
> the plan.

Pattern: the supervisor hands the planner the evidence and its own recommendation, and
routes operator questions through itself.

### Cook (M2-amend-cook, `/ak-cook`)

> A separate session, "M2-amend-review", will review your branches and merge them. You do
> NOT merge to master. … The operator approved the PRD text verbatim at 17:43; do not
> reword it. … Items 2 and 3 may run in parallel (disjoint files). Do NOT run
> `skill-mirror.sh sync` against the real ~/.hermes … The supervisor runs the real sync.
> Do NOT start phase 03 or phase 05. … Stop every Chrome process you start
> (`pgrep -fl dk-chrome-` empty at the end). Leave worktrees and branches in place for
> review.

Pattern: one branch and worktree per item, explicit out-of-scope phases, live systems
reserved for the supervisor or operator.

### Review + merge (M3-discover-review, `/ak-code-review`)

> Supervisor decisions on cook concerns: … accepted … you own the fix … pending operator
> questions. Do NOT change either; they don't block the merge.
>
> Merge order with dk/review-stage: M3-review-review is reviewing dk/review-stage in
> parallel; both edit SKILL.md's routing table … Whoever merges second resolves.
>
> What to check: … Tests are real (run a quick mutation on at least one). …
> Merge: fix small findings yourself on the branch (separate commits). Findings needing an
> operator decision: report with your recommendation, don't merge. After merging, mark the
> item done in roadmap.md, remove the worktree and delete the branch.

Pattern: the supervisor pre-decides each cook concern, and names the conflict owner for
parallel merges.

### Debug (judge-timeout-debug, `/ak-debug`)

> Your only job: prove the root cause of why `dk kit verify` ran ~1187 s although
> `judge.timeout_ms` is 120000 … Diagnosis only: write no product code, change no file
> outside your report. A live Hermes kit job is running right now. Do NOT run any dk
> command against it … If you need to reproduce, use a fixture in a throwaway copy, and
> stop every process you start. … Questions to answer with evidence: … Propose the minimal
> fix and a test that would fail today.

Pattern: evidence paths and concrete questions up front, a read-only boundary around a
live job, and output limited to one report.
