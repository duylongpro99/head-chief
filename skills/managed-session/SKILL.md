---
name: managed-session
description: Use when asked to start, stop, or close a Claude Code coding session under Herdr or herdr core / hc (e.g. "start a managed-session", "open a new claude session", "start a session with sonnet 5.5", "start a session with hc", "auto compact at 300k", "stop that managed-session", "close its pane"). Creates a Herdr pane (default, new tab in the current workspace) or an hc terminal (`--hc`) running `claude --dangerously-skip-permissions` (plain `claude` only if the user asks for permission prompts) with the auto-compact window set to 400k tokens unless overridden; can also stop the session and close its pane/terminal. Herdr mode requires HERDR_ENV=1; hc mode requires `hc` on PATH.
---

# managed-session

## Overview

Starts a new Claude Code session as a Herdr-managed pane in the current workspace (default), or as a herdr core terminal via the `hc` CLI (`--hc`), so it stays attached to and reachable from the active terminal. Every session starts with its auto-compact window pinned to 400k tokens unless `--compact-window` says otherwise. Run the bundled script instead of hand-rolling `herdr` calls — it encodes the exact `herdr` CLI shape this was verified against, which has drifted from the general `herdr` skill's own docs before.

Sibling skill `cx-session` does the same thing for Codex (`codex` instead of `claude`); the two share behavior and flags.

## When to Use

- Use when the user asks to start, open, or spin up a new Claude Code / "cc" session — optionally naming the pane, renaming the session itself, picking the model, choosing where it's placed (new tab vs. split in the active tab), running it under herdr core (`hc`) instead of Herdr, or changing the auto-compact threshold.
- Use when the user asks to stop, kill, or close a `managed-session` pane or hc terminal.

## Before running

Pick the backend. Herdr is the default; use `--hc` only when the user asks for herdr core / `hc`, or when Herdr isn't active and they still want a session.

- Herdr: verify `test "${HERDR_ENV:-}" = 1`. If this fails, tell the user this isn't running inside Herdr and offer `--hc` instead.
- hc: verify `command -v hc`. hc doesn't need `HERDR_ENV`.

## Usage

```bash
scripts/create-session.sh [--hc] [--p-name PANE_LABEL] [--s-name SESSION_NAME] [--model MODEL] [--compact-window TOKENS] [--split-r | --split-d] [--no-skip-perms]
```

Resolve the script path relative to this `SKILL.md`.

| Flag | Effect |
| --- | --- |
| *(none)* | Default: creates a new Herdr tab in the current workspace (`$HERDR_WORKSPACE_ID`) and starts `claude --dangerously-skip-permissions` in its pane, then focuses it. |
| `--hc` | Starts the session as a herdr core terminal with `hc run --bg --outlive-parent --cwd "$PWD" --label managed-session=claude` instead of a Herdr pane. It survives the caller's exit, and you attach with `hc attach <t>`. It can't be combined with `--split-r`/`--split-d`. |
| `--compact-window TOKENS` | Auto-compact window for the new session, default `400000`. Accepts `400000`, `400k` or `1m`, from 100k to 1m. Applied as `claude --settings '{"autoCompactWindow":N}'`. |
| `--split-r` | (Herdr only) Splits the caller's current pane to the right in the active tab instead of creating a new tab, and starts `claude` there. |
| `--split-d` | (Herdr only) Same as `--split-r`, but splits down. |
| `--p-name NAME` | Herdr: labels the new pane via `herdr pane rename` (a Herdr-level label, shown in sidebar/tab UI — separate from the agent's own session identity). hc: becomes the terminal's `--name`, which must be 1–32 chars of `a-z 0-9 - _` and unique among live terminals; you can then address it by that name. |
| `--no-skip-perms` | Launches plain `claude` without `--dangerously-skip-permissions`, so the session prompts for permissions normally. Pass this only when the user asks for permission prompts / a safe / non-bypass session. |
| `--s-name NAME` | Passed as `claude --name NAME` on the launch command line, so the CLI sets its own session display name (prompt box, `/resume` picker, terminal title) from the start. |
| `--model MODEL` | Passed as `claude --model MODEL`, so the session starts on that model. Accepts aliases (`sonnet`, `opus`, `haiku`, `opusplan`, `sonnet[1m]`), full model IDs (`claude-sonnet-5-5`), or human-friendly names like `"sonnet 5.5"`, `"Opus 5.5"`, `"claude haiku 4.5"` — these are normalized to `claude-<family>-<major>-<minor>` (e.g. `claude-sonnet-5-5`). Anything else is passed through verbatim. Omit to use the CLI's default model. |

`--split-r` and `--split-d` are mutually exclusive; the script rejects both together.

`create-session.sh` prints what it started. Herdr: `Started Claude Code in pane w8:p0 (tab w8:tE), auto-compact window 400000 tokens.` hc: `Started Claude Code in hc terminal t4 (name x), auto-compact window 400000 tokens. Attach with: hc attach t4`. That pane ID or terminal address (or hc name) is what `stop-session.sh` below takes.

### Stopping a session

```bash
scripts/stop-session.sh <pane_id>          # Herdr pane
scripts/stop-session.sh --hc <terminal>    # hc terminal: t4 or its name
```

Herdr: sends `/exit` into the pane so Claude Code quits on its own, then closes the pane regardless of whether that worked (`herdr pane close` also kills the process directly, so it's safe to run even if `/exit` didn't do anything, and a no-op if the pane is already gone).

hc: sends `/exit` only if the session is idle (`hc send --if idle`), then `hc kill` and `hc rm`, so the terminal doesn't linger in `hc ls --all`. A no-op if the terminal is already gone.

## Notes

- Sessions start with `--dangerously-skip-permissions` by default, meaning the new Claude Code session runs tools without asking. Only add `--no-skip-perms` when the user explicitly asks for permission prompts (e.g. "with permissions", "safe mode", "don't skip permissions").
- In Herdr mode the script polls (up to 60s) until the new pane reaches Herdr's `idle` agent status before applying `--p-name`, and prints a warning on stderr if it never does. A first-run Claude Code install with onboarding prompts (theme choice, trust dialog) can delay or prevent this — if `--p-name` doesn't apply, resolve the prompt yourself and rename the pane manually with `herdr pane rename <pane_id> NAME`.
- `--s-name` is applied via `claude`'s own `--name` startup flag, not a post-launch `/rename` injection — this avoids a race where text typed into Claude Code's input box right after startup can land as a paste (embedded newline inserts a line instead of submitting), leaving the command sitting unsubmitted.
- The auto-compact window is the size Claude Code compacts against: compaction fires at the window minus the autocompact buffer (about 33k tokens), so the default 400k compacts at roughly 367k. `/context` in the new session shows `Auto-compact window: 400k tokens`. If `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is set in the environment, it takes precedence over this setting. A model whose context is smaller than the window clamps it to the model's own window.
- Change the threshold when the user asks (e.g. "auto compact at 300k" → `--compact-window 300k`). Otherwise always rely on the 400k default; don't drop the flag's effect by launching `claude` by hand.
- In hc mode the `claude` process is launched directly (no shell, no `env` wrapper), so hc recognizes it as `claude-code` and reports its `idle`/`working` status. Use `hc read <t>`, `hc send <t> TEXT`, `hc wait <t>` and `hc attach <t>` for anything beyond start/stop.
- Use `--model` when the user names a model for the new session (e.g. "start a session with sonnet 5.5" → `--model "sonnet 5.5"`). Quote values that contain spaces. An unknown model name isn't validated by the script — `claude` itself will report it in the new pane.
- The create script prints the resulting pane and tab IDs on success. Use `herdr agent get <pane_id>`, `herdr pane read <pane_id> --source recent-unwrapped`, or the general `herdr` skill for anything beyond starting/naming/stopping the session.
- `stop-session.sh` closes whatever pane you point it at — it doesn't verify the pane is actually running Claude Code. Don't point it at a pane you didn't start with this skill unless the user clearly means that pane.
- Do not use the Herdr mode outside Herdr (use `--hc` instead), and do not reimplement its steps by hand when the script covers them — the installed `herdr` binary's actual CLI surface has previously diverged from its own bundled documentation, and the script was written against and verified against the real installed behavior.
