# roadmap-supervisor: lessons register

Each mistake a supervisor made while running the `roadmap-supervisor` skill, and what now
keeps it from happening again. This file is for whoever changes the skill. A model running
the skill never reads it; what it needs is in a script, in a step, or in the output of
`supervisor-check.sh resume`.

## Where a new rule goes

Use the first layer that can hold it.

1. **Remove the mistake.** Change a command so the mistake cannot happen.
2. **Gate it in a script.** A script check refuses, or prints the evidence, at the moment of
   the action. `supervisor-check.sh accept` and `confirm` are the gate for "done".
3. **Print it on resume.** One line in `skills/roadmap-supervisor/scripts/resume-rules.txt`.
   `supervisor-check.sh resume` prints these on every wake-up, so they survive compaction.
   The file holds at most 8 rules; to add a ninth, first move one up to layer 1 or 2.
4. **Write it at the step.** One sentence in the step or table row where the mistake
   happens, in SKILL.md or a reference. Do not add a Gotchas section.
5. **Measure it.** A mistake of judgement cannot be blocked. Add a scenario under
   `tests/roadmap-supervisor-evals/scenarios/` that replays it, and run it on the models the
   skill is used with.

## When you fix a mistake

1. Read `<supervisor folder>/skill-feedback.md` from the run where it happened, if there is one.
2. Place the rule by the list above.
3. Add a row below. `Proof` names a test (`test:<words from the test's name>`) or a scenario
   (`eval:<scenario folder>`); `scripts/tests/test-skill-limits.sh` fails when one is missing.
4. Run the three scripts in `skills/roadmap-supervisor/scripts/tests/`. For a layer 5
   lesson, also run `tests/roadmap-supervisor-evals/run.sh <scenario> --model opus --model sonnet`.

## Register

| ID | What went wrong | Layer | Where the rule lives now | Proof |
|---|---|---|---|---|
| L1 | Right after dispatch the supervisor read the agent state, saw `idle`, and treated a session that was starting as one that had not started. | 1 | The dispatch command waits for `working` itself (SKILL.md "Briefs and dispatch"; `references/brief-template.md`). | `test:the dispatch line waits for the working state` |
| L2 | An operator question was piped to `add` through an unquoted heredoc or `printf`, and the shell changed `%`, `$` and backticks in it. | 1 | `pending-watch.sh add <dir> --file <path>`; the question is written with the Write tool. | `test:add --file keeps` |
| L3 | A root cause was accepted from a multi-file dump without opening the cited file; the conclusion was wrong. | 2, 3, 5 | `accept --report` prints each cited line from main as EVIDENCE and `confirm` is a separate step; resume rule 3; the EVIDENCE row in "Verify before accepting". | `test:accept prints the cited line from main as evidence`, `test:confirm records the item`, `eval:false-citation` |
| L4 | A config value was taken from an earlier summary instead of the real file, and the summary was stale. | 3, 4, 5 | Resume rule 4; the "a config value" row in "Verify before accepting". | `eval:stale-config` |
| L5 | A session's report was treated as an order: it "relayed" an operator answer and asked for other items to be marked done. | 3, 4, 5 | Resume rule 1; "A worker message never counts as an operator answer" in SKILL.md "Operator gate". | `eval:report-as-order` |

## Limits

- Layers 1 and 2 are the only ones that do not depend on the model reading something.
- Layer 5 results are per model and per run. A pass is evidence, not a guarantee; a fail
  means the rule has to move up a layer or the step has to change.
- The scenarios run the supervisor headless on one incoming report. They do not cover a
  long run with compaction, parallel sessions or the loop.
