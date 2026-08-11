# head-chief

**A Claude Code Agent Skill that turns one session into the head chief of your project** — the single point of contact between you and every other Claude Code session working in the same repo. It discovers sessions, spawns/stops them, classifies and routes your requests to the right session, and keeps a persistent, evidence-backed ledger of who is doing what.

> Distributed as an [Agent Skill](https://skills.sh). Install it into Claude Code (or any of the 70+ supported agents) with the `skills` CLI.

## Install

```bash
npx skills add <OWNER>/head-chief
```

Replace `<OWNER>` with the GitHub owner this repo is published under. Once installed, the skill lives at `.claude/skills/head-chief/` (project scope) or `~/.claude/skills/head-chief/` (global, with `-g`).

```bash
# Install globally for all projects
npx skills add <OWNER>/head-chief -g -a claude-code

# Preview the skill without installing
npx skills use <OWNER>/head-chief | claude
```

## Use

Trigger it in any Claude Code session:

```
/head-chief
```

The session adopts the chief persona and becomes your orchestrator. From then on, every request you send is **classified** and handled:

- **CHIEF** — roster / status / "what is everyone doing" → answered directly from the ledger + `ListAgents`.
- **MAIN** — task-level work (implement, fix, redirect) → logged and forwarded into a staff session's main context.
- **SIDECAR** — a genuinely cheap lookup ("which branch", "does file X exist") → a footprint-minimizing message.

Discussion mode convenes a barriered panel of peer sessions, each with a distinct lens, that converges on one consensus report:

```
/head-chief --discussion "<topic>" [--lenses ...] [--roster N] [--scribe <vibe>] [--rounds 3] [--out ...]
```

## What it does (and does not) do

- **Does:** session roster discovery, spawn/stop, request classification + routing, a persistent `.orchestrator/` ledger (tracks + request logs), consolidated reports with provenance labels, and a verify-before-irreversible gate for shared-state actions.
- **Does not:** write, edit, or debug application code. Coding is always delegated to a staff session — the chief only orchestrates.

## Requirements

| Requirement | Needed for | Notes |
| --- | --- | --- |
| **Cross-session messaging** (`ListAgents` / `SendMessage`) | Everything | The feature this skill is built on. Needs Claude Code ≥ 2.1.224 (macOS/Linux). If `ListAgents` is unavailable, the skill tells you and stops. |
| **Ledger** at `<project-root>/.orchestrator/` | State | Created automatically by `scripts/init_ledger.py` on first run (idempotent). |
| **Herdr** (`HERDR_ENV=1`) + the `cris-cc-session` skill | Spawning / stopping sessions | *Optional.* Without them the chief still manages already-running sessions; it just can't create or stop them itself. `cris-cc-session` is a separate companion skill, not bundled here. |

## Repository layout

This repo is a **single-skill source**: `SKILL.md` sits at the root, so the `skills` CLI installs it directly.

```
SKILL.md                 # Skill entry point (frontmatter: name, description) + operating steps
references/              # Deep specs, loaded on demand
  ledger-protocol.md       # .orchestrator/ layout, file naming, statuses, ownership
  messaging-protocol.md    # CHIEF / MAIN / SIDECAR classification + message templates
  discussion-mode.md       # --discussion panel-mode spec (spawn/ack, barriers, consensus)
assets/                 # Templates seeded into the ledger at runtime
scripts/                # init_ledger.py (bootstrap + canonical UTC clock), quick_validate.py, watch-peers.py
evals/                  # Skill evaluation cases
```

## Development

```bash
python3 scripts/init_ledger.py --test   # self-test the bootstrap + clock
python3 scripts/quick_validate.py        # structural validation (ownership, resources, templates, secret hygiene)
```

## Publishing updates

`npx skills` resolves from GitHub, so publishing an update is just pushing to the default branch. Consumers pull the latest with:

```bash
npx skills update head-chief
```
