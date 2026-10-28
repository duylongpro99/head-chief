# head-chief

**A Claude Code Agent Skill collection that turns one session into the head chief of your project** — the single point of contact between you and every other Claude Code session working in the same repo. It discovers sessions, spawns/stops them, classifies and routes your requests to the right session, and keeps a persistent, evidence-backed ledger of who is doing what.

This repo ships **four skills** that work together:

| Skill | Purpose |
| --- | --- |
| **`head-chief`** | The orchestrator persona: roster discovery, request classification + routing, the `.orchestrator/` ledger, consolidated reports, and discussion mode. |
| **`managed-session`** | The lifecycle helper the chief uses to **spawn and stop** Claude Code sessions as Herdr panes. Requires `HERDR_ENV=1`. |
| **`pr-review-loop`** | Review GitHub PRs with a separate session and loop review → verify/fix → re-review until approved. Cook mode (run by the implementer), reviewer mode (finds and wakes or restores the implementer session) and `--review-only`. Uses `managed-session` when installed. |
| **`envoy-peer`** | Hand one task with acceptance criteria to an agent CLI of another kind (codex, grok, omp, agy, …) in its own Herdr pane, let an independent reviewer pane check the work, and loop fix → re-review until accepted. Only the status, a short summary and file paths come back. Requires `HERDR_ENV=1`. |

> Distributed as [Agent Skills](https://skills.sh). Install them into Claude Code (or any of the 70+ supported agents) with the `skills` CLI.

## Install

```bash
# Install the skills (the CLI lists them and lets you choose)
npx skills add duylongpro99/head-chief

# Install everything non-interactively
npx skills add duylongpro99/head-chief --all

# Install just the orchestrator (skip session lifecycle)
npx skills add duylongpro99/head-chief --skill head-chief

# Install just the cross-kind envoy
npx skills add duylongpro99/head-chief --skill envoy-peer
```

Installed skills live at `.claude/skills/<name>/` (project scope) or `~/.claude/skills/<name>/` (global, with `-g`).

```bash
# Install globally for all projects, Claude Code only
npx skills add duylongpro99/head-chief --all -g -a claude-code

# Preview a skill without installing
npx skills use duylongpro99/head-chief --skill head-chief | claude
```

## Use

Trigger the orchestrator in any Claude Code session:

```
/head-chief
```

The session adopts the chief persona and becomes your orchestrator. From then on, every request you send is **classified** and handled:

- **CHIEF** — roster / status / "what is everyone doing" → answered directly from the ledger + `ListAgents`.
- **MAIN** — task-level work (implement, fix, redirect) → logged and forwarded into a staff session's main context.
- **SIDECAR** — a genuinely cheap lookup ("which branch", "does file X exist") → a footprint-minimizing message.

When the chief needs a new session, it invokes `managed-session` to spawn one (and to stop it later). Discussion mode convenes a barriered panel of peer sessions, each with a distinct lens, that converges on one consensus report:

```
/head-chief --discussion "<topic>" [--lenses ...] [--roster N] [--scribe <vibe>] [--rounds 3] [--out ...]
```

### Hand a task to another agent kind

```
/envoy-peer [--kind codex] [--reviewer claude] [--max-rounds 3] "<task>"
/envoy-peer --cleanup --all
```

The session writes a brief with acceptance criteria, opens the envoy in a Herdr pane next to it, and has a reviewer pane (by default the controller's own kind) check the result against that brief. The envoy runs with full permission in the same working tree, so do not edit the tree while a run is going. Each CLI keeps its own credentials: the skill never reads, stores or types them, and a login screen is left for you to finish in the pane. Runs live under `.envoy/runs/` at the git root; the folder ignores itself.

## What it does (and does not) do

- **Does:** session roster discovery, spawn/stop, request classification + routing, a persistent `.orchestrator/` ledger (tracks + request logs), consolidated reports with provenance labels, and a verify-before-irreversible gate for shared-state actions.
- **Does not:** write, edit, or debug application code. Coding is always delegated to a staff session — the chief only orchestrates.

## Requirements

| Requirement | Needed for | Notes |
| --- | --- | --- |
| **Cross-session messaging** (`ListAgents` / `SendMessage`) | Everything | The feature `head-chief` is built on. Needs Claude Code ≥ 2.1.224 (macOS/Linux). If `ListAgents` is unavailable, the skill tells you and stops. |
| **Ledger** at `<project-root>/.orchestrator/` | State | Created automatically by `head-chief`'s `init_ledger.py` on first run (idempotent). |
| **Herdr** (`HERDR_ENV=1`) | Spawning / stopping sessions | Needed by the bundled `managed-session` skill. Without it the chief still manages already-running sessions; it just can't create or stop them itself. |
| **Herdr**, `jq`, `git` | `envoy-peer` | Herdr ≥ 0.8.0 with `HERDR_ENV=1`; there is no fallback outside Herdr. Bash 3.2 or later. |
| **Agent CLIs** (codex, grok, omp, agy, claude) | `envoy-peer` | Install and log in to the kinds you want to use. Launch flags for each kind live in `skills/envoy-peer/references/kinds.json`; a kind without a verified row is not offered. |

## Repository layout

Multi-skill source: each skill lives under `skills/<name>/` with its own `SKILL.md`, so the `skills` CLI discovers each of them.

```
skills.sh.json             # skills.sh grouping manifest
skills/
  head-chief/
    SKILL.md               # Orchestrator entry point + operating steps
    references/            # Deep specs, loaded on demand
      ledger-protocol.md      # .orchestrator/ layout, file naming, statuses, ownership
      messaging-protocol.md   # CHIEF / MAIN / SIDECAR classification + message templates
      discussion-mode.md      # --discussion panel-mode spec (spawn/ack, barriers, consensus)
    assets/                # Templates seeded into the ledger at runtime
    scripts/               # init_ledger.py, quick_validate.py, watch-peers.py
    evals/                 # Skill evaluation cases
  managed-session/
    SKILL.md               # Session lifecycle helper (Herdr)
    scripts/               # create-session.sh, stop-session.sh
  pr-review-loop/
    SKILL.md               # Cook / reviewer / review-only PR review loop
    references/messages.md # Messages exchanged between the two sessions
    scripts/               # session.sh (Herdr start/restore/compact/stop), find-implementer.py
  envoy-peer/
    SKILL.md               # Controller flow: pick kinds, brief, dispatch, review loop, cleanup
    references/            # run-contract.md, kinds.json, brief/result/review templates
    scripts/               # probe, state, new-run, start, prompt-wait, run-state, check-brief, stop, cleanup
    evals/                 # Skill evaluation cases
install.sh                 # Symlink skills from this checkout into a host's skill folder
```

## Development

```bash
cd skills/head-chief
python3 scripts/init_ledger.py --test   # self-test the bootstrap + clock
python3 scripts/quick_validate.py        # structural validation (ownership, resources, templates, secret hygiene)
```

To try a skill from this checkout without publishing, link it into a host's skill folder:

```bash
./install.sh                    # ~/.claude/skills/envoy-peer -> skills/envoy-peer
./install.sh --project          # <git root>/.claude/skills; refused unless git ignores the link
./install.sh --uninstall        # remove only links that point into this checkout
./install.sh --help             # other destinations, --skill, --force, --dry-run
```

The links follow this checkout's current HEAD: switching branches here changes the skill everywhere it is linked.

## Publishing updates

`npx skills` resolves from GitHub, so publishing an update is just pushing to the default branch. Consumers pull the latest with:

```bash
npx skills update head-chief managed-session pr-review-loop envoy-peer
```
