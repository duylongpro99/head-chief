# Permission suggestions

Learn allow rules from the permission prompts the operator answered in this supervisor and
in every worker session. `scripts/permission-suggest.py` does the work without a model. You
only run it, add its item to the ledger and apply the answer.

## Where the data comes from

A global `PermissionRequest` hook runs `permission-suggest.py log` in every Claude Code
session on the machine. Workers are included, and the operator keeps approving prompts in
the worker panes as usual. Each prompt becomes one line in `~/.claude/permission-log.jsonl`
with the time, cwd, Herdr pane, tool and command. The log records that a prompt appeared,
not whether the operator allowed it. That is why every rule goes through the operator.

If the hook is not installed, the log is empty and `suggest` prints nothing. Do not install
the hook yourself: changing the operator's settings is their decision. Mention it once in
the final report.

## When to run it

1. After each milestone or phase merge, before the Reporting message.
2. At cleanup, before `pending-watch.sh close`, so the item reaches
   `pending-decisions.final.md`.

When the last item is merged, both points are the same moment: run it once, at cleanup.
Never run it on an ordinary wake-up.

## Steps

```bash
S=<skill-dir>/scripts/permission-suggest.py
python3 -I $S suggest <dir>
```

- **Nothing printed:** no new rule reached the threshold (3 prompts since `<dir>` was
  created). Do nothing more.
- **Output printed:** the first line is an item file the script wrote. Pass it to
  `pending-watch.sh add <dir> --file <that path>` like any other question, then tell the
  operator the `D<n>` in one chat line. It blocks no work, so open no dialog for it.

The script classifies each rule. `global` rules are commands that work anywhere, such as
`herdr tab get`. They go to `~/.claude/settings.json`. `project` rules are script paths.
They go to `~/.claude/project-local-allow.json`, which a SessionStart hook seeds into each
project's `.claude/settings.local.json`. The script never proposes commands that delete,
send data off the machine, run inline code or touch secrets. It also skips rules that are
already allowed, and rules that were proposed before.

## Applying the answer

Record the answer as usual, then:

| Operator says | Run |
|---|---|
| some IDs, for example `P1 P3` | `apply <dir> P1 P3`, then `decline <dir>` with the other IDs of that item |
| `tất cả`, all | `apply <dir>` with every ID of that item |
| `không`, none | `decline <dir>` with every ID of that item |

`apply` backs up `~/.claude/settings.json` first. A rule takes effect in sessions started
after it is applied, so the next milestone's workers benefit. A declined rule is never
proposed again for this `<dir>`.

Tests: `scripts/tests/test-permission-suggest.sh`.
