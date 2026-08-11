# head-chief

**A Claude Code Agent Skill collection that turns one session into the head chief of your project** — the single point of contact between you and every other Claude Code session working in the same repo. It discovers sessions, spawns/stops them, classifies and routes your requests to the right session, and keeps a persistent, evidence-backed ledger of who is doing what.

This repo ships **two skills** that work together:

| Skill | Purpose |
| --- | --- |
| **`head-chief`** | The orchestrator persona: roster discovery, request classification + routing, the `.orchestrator/` ledger, consolidated reports, and discussion mode. |
| **`managed-session`** | The lifecycle helper the chief uses to **spawn and stop** Claude Code sessions as Herdr panes. Requires `HERDR_ENV=1`. |

> Distributed as [Agent Skills](https://skills.sh). Install them into Claude Code (or any of the 70+ supported agents) with the `skills` CLI.

## Install

```bash
# Install both skills (the CLI lists them and lets you choose)
npx skills add <OWNER>/head-chief

# Install everything non-interactively
npx skills add <OWNER>/head-chief --all

# Install just the orchestrator (skip session lifecycle)
npx skills add <OWNER>/head-chief --skill head-chief
```

Replace `<OWNER>` with the GitHub owner this repo is published under. Installed skills live at `.claude/skills/<name>/` (project scope) or `~/.claude/skills/<name>/` (global, with `-g`).

```bash
# Install globally for all projects, Claude Code only
npx skills add <OWNER>/head-chief --all -g -a claude-code

# Preview a skill without installing
npx skills use <OWNER>/head-chief --skill head-chief | claude
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

## What it does (and does not) do

- **Does:** session roster discovery, spawn/stop, request classification + routing, a persistent `.orchestrator/` ledger (tracks + request logs), consolidated reports with provenance labels, and a verify-before-irreversible gate for shared-state actions.
- **Does not:** write, edit, or debug application code. Coding is always delegated to a staff session — the chief only orchestrates.

## Requirements

| Requirement | Needed for | Notes |
| --- | --- | --- |
| **Cross-session messaging** (`ListAgents` / `SendMessage`) | Everything | The feature `head-chief` is built on. Needs Claude Code ≥ 2.1.224 (macOS/Linux). If `ListAgents` is unavailable, the skill tells you and stops. |
| **Ledger** at `<project-root>/.orchestrator/` | State | Created automatically by `head-chief`'s `init_ledger.py` on first run (idempotent). |
| **Herdr** (`HERDR_ENV=1`) | Spawning / stopping sessions | Needed by the bundled `managed-session` skill. Without it the chief still manages already-running sessions; it just can't create or stop them itself. |

## Repository layout

Multi-skill source: each skill lives under `skills/<name>/` with its own `SKILL.md`, so the `skills` CLI discovers both.

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
```

## Development

```bash
cd skills/head-chief
python3 scripts/init_ledger.py --test   # self-test the bootstrap + clock
python3 scripts/quick_validate.py        # structural validation (ownership, resources, templates, secret hygiene)
```

## Publishing updates

`npx skills` resolves from GitHub, so publishing an update is just pushing to the default branch. Consumers pull the latest with:

```bash
npx skills update head-chief managed-session
```
