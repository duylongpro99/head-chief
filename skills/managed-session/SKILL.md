---
name: managed-session
description: Use when asked to start, stop, or close a Claude Code coding session under Herdr (e.g. "start a managed-session", "open a new claude session", "stop that managed-session", "close its pane"). Creates a Herdr pane running `claude`, by default in a new tab in the current workspace; can also stop the session and close its pane. Requires HERDR_ENV=1.
---

# managed-session

## Overview

Starts a new Claude Code session as a Herdr-managed pane in the current workspace, so it stays attached to and reachable from the active terminal. Run the bundled script instead of hand-rolling `herdr` calls — it encodes the exact `herdr` CLI shape this was verified against, which has drifted from the general `herdr` skill's own docs before.

Sibling skill `cx-session` does the same thing for Codex (`codex` instead of `claude`); the two share behavior and flags.

## When to Use

- Use when the user asks to start, open, or spin up a new Claude Code / "cc" session — optionally naming the pane, renaming the session itself, or choosing where it's placed (new tab vs. split in the active tab).
- Use when the user asks to stop, kill, or close a `managed-session` pane.

## Before running

Verify Herdr is active:

```bash
test "${HERDR_ENV:-}" = 1
```

If this fails, tell the user this isn't running inside Herdr and stop.

## Usage

```bash
scripts/create-session.sh [--p-name PANE_LABEL] [--s-name SESSION_NAME] [--split-r | --split-d]
```

Resolve the script path relative to this `SKILL.md`.

| Flag | Effect |
| --- | --- |
| *(none)* | Default: creates a new Herdr tab in the current workspace (`$HERDR_WORKSPACE_ID`) and starts `claude` in its pane, then focuses it. |
| `--split-r` | Splits the caller's current pane to the right in the active tab instead of creating a new tab, and starts `claude` there. |
| `--split-d` | Same as `--split-r`, but splits down. |
| `--p-name NAME` | Labels the new Herdr pane via `herdr pane rename` (a Herdr-level label, shown in sidebar/tab UI — separate from the agent's own session identity). |
| `--s-name NAME` | Passed as `claude --name NAME` on the launch command line, so the CLI sets its own session display name (prompt box, `/resume` picker, terminal title) from the start. |

`--split-r` and `--split-d` are mutually exclusive; the script rejects both together.

`create-session.sh` prints the pane ID it started (e.g. `Started Claude Code in pane w8:p0 (tab w8:tE).`) — that pane ID is what `stop-session.sh` below takes.

### Stopping a session

```bash
scripts/stop-session.sh <pane_id>
```

Sends `/exit` into the pane so Claude Code quits on its own, then closes the pane regardless of whether that worked (`herdr pane close` also kills the process directly, so it's safe to run even if `/exit` didn't do anything, and a no-op if the pane is already gone).

## Notes

- The script waits (up to 30s) for the new pane to reach Herdr's `idle` agent status before applying `--p-name`. A first-run Claude Code install with onboarding prompts (theme choice, trust dialog) can delay or prevent this — if `--p-name` doesn't apply, resolve the prompt yourself and rename the pane manually with `herdr pane rename <pane_id> NAME`.
- `--s-name` is applied via `claude`'s own `--name` startup flag, not a post-launch `/rename` injection — this avoids a race where text typed into Claude Code's input box right after startup can land as a paste (embedded newline inserts a line instead of submitting), leaving the command sitting unsubmitted.
- The create script prints the resulting pane and tab IDs on success. Use `herdr agent get <pane_id>`, `herdr pane read <pane_id> --source recent-unwrapped`, or the general `herdr` skill for anything beyond starting/naming/stopping the session.
- `stop-session.sh` closes whatever pane you point it at — it doesn't verify the pane is actually running Claude Code. Don't point it at a pane you didn't start with this skill unless the user clearly means that pane.
- Do not use this skill outside Herdr, and do not reimplement its steps by hand when the script covers them — the installed `herdr` binary's actual CLI surface has previously diverged from its own bundled documentation, and the script was written against and verified against the real installed behavior.
