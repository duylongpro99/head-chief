# Run contract

The contract every envoy-peer script and `SKILL.md` follow. `run.json` is the
single source of truth for a run: after a context compaction, read it before
doing anything else.

## Layout

```text
<git toplevel of --cwd, or --cwd itself>/.envoy/
  .gitignore              # contains "*": the folder ignores itself, the project's own .gitignore is never edited
  runs/<YYMMDD-HHMM>-<slug>-<nonce>/
    run.json              # ledger (mode 600, written atomically under run.json.lock)
    brief.md              # written by the controller before dispatch
    result.md             # written by the envoy, rewritten every round
    review-1.md … review-n.md   # written by the reviewer, one per round
    baseline-status.txt   # `git status --short -uall` before the envoy pane opened
    baseline-untracked.sha      # sha256 of every untracked file before the envoy pane opened
    guard-<n>.manifest    # per-file state before reviewer turn n (guard begin)
    guard-<n>.after.manifest  # the same after the turn (guard end)
    smoke.txt             # only when onboarding ran the smoke test
```

The run folder is created with `umask 077` and `mkdir` without `-p` for the
leaf, so two runs can never share a folder.

## run.json

All timestamps are ISO-8601 UTC (`2026-10-28T08:00:00Z`). Elapsed time is
computed with `jq 'now - (.x | fromdateiso8601)'`, never `date -d`.

```json
{
  "version": 1,
  "run_id": "261028-1500-add-install-a1b2c3",
  "nonce": "a1b2c3",
  "run_dir": "/abs/repo/.envoy/runs/261028-1500-add-install-a1b2c3",
  "cwd": "/abs/repo",
  "created_at": "2026-10-28T08:00:00Z",
  "controller": {"pane": "wC:p8B", "kind": "claude"},
  "envoy":    {"kind": "codex",  "name": "env-codex-a1b2c3",  "label": "envoy codex add-install",    "model": null,
               "pane": null, "tab": null, "terminal_id": null, "command": null,
               "started_at": null, "prompted_at": null, "settled_at": null, "last_status": null, "closed_at": null},
  "reviewer": {"kind": "claude", "name": "rev-claude-a1b2c3", "label": "reviewer claude add-install", "model": null,
               "pane": null, "tab": null, "terminal_id": null, "command": null,
               "started_at": null, "prompted_at": null, "settled_at": null, "last_status": null, "closed_at": null},
  "baseline": {"head": null, "stash_sha": null, "dirty": null, "status_file": "baseline-status.txt",
               "untracked_manifest": "baseline-untracked.sha", "git_meta_sha": null, "note": null},
  "guard": {},
  "round": 0, "max_rounds": 3, "timeout_minutes": 60, "placement": "split",
  "dispatched_at": null,
  "status": "created", "final_status": null,
  "updated_at": "2026-10-28T08:00:00Z"
}
```

- `pane` / `terminal_id` identify the pane a script opened. A pane is closed
  only when both still match (`herdr pane list`); Herdr never reuses a closed
  pane id, and the terminal id guards against anything else.
- `command` is the argv passed to `herdr agent start` (launch args from
  `kinds.json`, plus the model flag when a model is set). No credentials.
- `processes_at_stop` (added by `stop.sh`) lists `{pid, cwd, command}` of the
  pane's foreground processes just before the pane closed; `command` is the
  executable name only.
- `guard.<n>` holds `before` / `after` snapshots (`head`, `index_sha`,
  `manifest_sha`) around reviewer turn `n`, and `clean: true|false`.
- `baseline.stash_sha` is `git stash create` (a commit object that touches
  neither the tree nor the index); it equals `head` when the tree was clean.
  `git stash create` leaves untracked files out, so `baseline-untracked.sha`
  covers them. Outside a git repository every baseline value is `null` and
  `note` says why.

`status` is one of `created | dispatched | reviewing | fixing | accepted |
concerns | blocked | timeout | cleaned`.

| Writer | Fields |
|--------|--------|
| `new-run.sh` | the whole file, `status: created` |
| `start.sh` | `<role>.pane/tab/terminal_id/command/started_at/last_status`, `baseline.*` (envoy, first start), `status: dispatched` (envoy, from `created`) or `reviewing` (reviewer) |
| `prompt-wait.sh` | `<role>.prompted_at/settled_at/last_status`, `dispatched_at` (first envoy prompt), `round` (with `--round`), `status: timeout` |
| `run-state.sh set` | `round`, `status` (`fixing`, `accepted`, `concerns`, `blocked`, …), `final_status`, `max_rounds`, `timeout_minutes` |
| `run-state.sh guard` | `guard.<n>` |
| `stop.sh` | `<role>.processes_at_stop`, `<role>.closed_at` |
| `cleanup.sh` | `final_status` (the status before cleanup, unless already set), `status: cleaned` |

Every write goes through `json_write_atomic` inside the `run.json.lock` mkdir
lock (bash 3.2 compatible, waits up to 5 s, breaks a lock older than 30 s).

## Exit codes

Shared by every script except `probe.sh auth`, which prints
`ready | not-ready | no-probe` and exits 0 once the probe decided, 1 when the
kind has no row in `kinds.json`.

| Code | Meaning |
|------|---------|
| 0 | ok / settled |
| 1 | environment, Herdr, or kind error (kind missing from `kinds.json`, same kind as the controller, not installed) |
| 2 | usage error |
| 3 | still running: call `prompt-wait.sh` again without `--text` |
| 4 | needs the user: pane is `blocked`, or `agent start` failed (trust, login or onboarding dialog); the pane stays open. `prompt-wait.sh` says whether its `--text` was sent |
| 5 | the run's total timeout (`timeout_minutes` since `dispatched_at`) passed |
| 6 | `agent_prompt_stalled` and the agent is not `working` |
| 7 | settled, but the expected file is `missing`, `stale`, has no `Round: N` line (`no-round`), or has no single valid result line (`no-match`); also a review without a conflicts section (`run-state.sh conflicts` prints `missing`) |
| 8 | refused to send `--text`: the role has `prompted_at` without `settled_at` and the agent is `working` |
| 9 | refused to close: the pane does not belong to this run (`terminal_id` differs) |
| 10 | the pane or agent is gone (`agent_not_found` while waiting, or the pane is not in `herdr pane list`) |
| 11 | `start.sh`: the pane opened but the agent was not ready in time; call `start.sh` again to resume |

## Herdr semantics

Verified against Herdr 0.8.0 (`herdr --skill`, live checks on 2026-10-28):

- `idle` means ready and the tab has been seen in the UI; `done` is the same
  ready state while the tab has not been seen yet. The scripts open panes with
  `--no-focus`, so a finished envoy usually reports `done`. **Settled =
  `idle` or `done`**; the two are equivalent.
- `blocked` means Herdr detected an approval prompt or question in the agent UI.
- `herdr agent wait` and `herdr agent prompt --wait` match `idle | done |
  blocked` by default. The scripts never pass `--until` (repeating the
  default is discouraged, and `--until idle` alone would miss `done`).
- `herdr agent prompt --wait` requires a state change within 5 s when the
  agent was not working; otherwise it fails with `agent_prompt_stalled`. It
  does not track turns: when the agent is already working, that turn's
  completion matches. So `prompt-wait.sh` only sends to a settled agent and
  refuses a duplicate send (exit 8).
- `herdr agent start <name> --kind K --pane P --timeout MS -- <args>` succeeds
  only when the agent is detected and ready for input (`--timeout` ≤ 300000).
  It needs the pane at an interactive shell prompt.
- Agent names must be unique among live agents and disappear when the agent
  exits. The scripts address agents by pane id; the name (`env-<kind>-<nonce>`
  / `rev-<kind>-<nonce>`) only keeps them recognisable in `herdr agent list`.
- `herdr agent get <pane|name>` returns `.result.agent.{agent, agent_status,
  pane_id, terminal_id, cwd}`, or `{"error":{"code":"agent_not_found"}}` with
  exit 1 for a shell pane, a closed pane, and an unknown name alike.
- Errors are JSON on stderr (`.error.code`: `agent_not_found`, `timeout`,
  `agent_prompt_stalled`, …); results are JSON on stdout. A successful
  `agent wait` / `agent prompt --wait` prints the agent object
  (`.result.agent.agent_status` is the matched state).
- `herdr pane list` returns `.result.panes[]` with `pane_id`, `terminal_id`,
  `label`, `agent`, `agent_status`.

## Waiting inside a host tool limit

`prompt-wait.sh` waits at most `--wait-ms` (default 540000, clamped to
570000) per call, then exits 3. The caller's tool timeout must be at least
`wait-ms + 30000`: in Claude Code pass `timeout: 600000` to the Bash tool, or
run the call in the background. A run longer than nine minutes is a loop of
calls without `--text`, bounded by `timeout_minutes`.

## Expected-file checks

With `--expect FILE --match REGEX`, a settled turn is accepted only when the
file exists, was modified after the turn being consumed, carries `Round: N`
when `--round N` is given, and has exactly one line matching `REGEX`. Only that
validated line is printed. "The turn being consumed" is the prompt sent by this
call or still outstanding from an earlier call (`prompted_at` without
`settled_at`). When a call without `--text` finds no outstanding prompt, the
file must be newer than the role's last `settled_at`; otherwise it is `stale`.
