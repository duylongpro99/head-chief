# Permission suggestions

Learn allow rules from the permission prompts the operator answered in this supervisor and
in every worker session. `scripts/permission-suggest.py` does the work without a model. You
run it and apply the answer.

## Setup (operator, once per machine)

The feature needs two hooks in `~/.claude/settings.json`. Do not install them yourself:
changing the operator's settings is their decision. If they are missing, the log stays empty
and `suggest` prints nothing. Mention that once in the final report and show this snippet:

```json
"hooks": {
  "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "timeout": 5,
    "command": "python3 -I <skill-dir>/scripts/permission-suggest.py log" }] }],
  "SessionStart": [{ "matcher": "^(startup|resume|clear|compact)$", "hooks": [{ "type": "command", "timeout": 10,
    "command": "python3 -I <skill-dir>/scripts/permission-suggest.py seed" }] }]
}
```

- `log` records each permission prompt from every session on the machine, workers
  included, in `~/.claude/permission-log.jsonl`: time, cwd, Herdr pane, tool and command.
  It records that a prompt appeared, not whether the operator allowed it. The file is
  mode 600, but it keeps raw commands (up to 1,000 characters), so a token typed inline
  in a command ends up there too.
- `seed` copies the project rules from `~/.claude/project-local-allow.json` into the
  `.claude/settings.local.json` of each git project a session starts in.

## When to run it

1. After each milestone or phase merge, before the Reporting message.
2. At cleanup, before `pending-watch.sh close`, so the item reaches
   `pending-decisions.final.md`.

When the last item is merged, both points are the same moment: run it once, at cleanup.
Never run it on an ordinary wake-up.

## Steps

```bash
python3 -I <skill-dir>/scripts/permission-suggest.py suggest <dir>
```

- **Nothing printed:** no new rule reached the threshold (3 prompts since the supervision
  started). Do nothing more.
- **Output printed:** the script already added the ledger item through
  `pending-watch.sh add`. The first line is its `D<n>`. Tell the operator the `D<n>` in one
  chat line. The item blocks no work, so open no dialog for it. Pass on any stderr warning
  from `add`, such as no watcher running, as `add` itself would require.
- **Exit 1:** the ledger add failed and nothing was marked. The next run proposes the same
  rules again.

## What gets proposed

Only shapes on an allowlist, each still checked by the operator:

- `global` rules, written to `~/.claude/settings.json`:
  - commands that only read, used without a subcommand, such as `ls` or `jq`;
  - a subcommand with a read verb and no risky word, such as `herdr tab get`, `git status`
    or `gh pr view`. `test`, `build`, `vet` and `check` count as reads even though they run
    the project's own code;
  - MCP tools whose action starts with `get`, `list`, `read`, `search`, `find`, `describe`,
    `view` or `show`.
- `project` rules, written to `~/.claude/project-local-allow.json`: the absolute path of an
  existing script, resolved against the cwd it ran in, never in a temp or system folder.

The script skips commands with substitution, redirection into a file or secret-looking
text, wrappers and inline code (`timeout`, `nohup`, `-c`, `run`, `dlx`), rules already
allowed or denied, and rules proposed before. The allowlist narrows what reaches the
operator. It does not make a rule safe, so the question asks them to read each line.

## Applying the answer

Record the answer as usual, then:

| Operator says | Run |
|---|---|
| some IDs, for example `P1 P3` | `apply <dir> P1 P3`, then `decline <dir> D<n>` |
| `tất cả`, all | `apply <dir> D<n>` |
| `không`, none | `decline <dir> D<n>` |

`D<n>` stands for every rule of that item that is still proposed. `apply` backs up
`~/.claude/settings.json` first and keeps the newest three backups. A rule takes effect in
sessions started after it is applied, so the next milestone's workers benefit. A declined
rule is never proposed again for this `<dir>`.

Tests: `scripts/tests/test-permission-suggest.sh`.
