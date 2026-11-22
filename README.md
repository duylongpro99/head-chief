# head-chief

**One Claude Code session to run all the others.**

You have several Claude Code sessions open in one repo: one is refactoring auth, one is fixing a bug, one is writing docs. Soon you are the router, copying context between tabs and asking each one what it is doing. `head-chief` turns one session into the **chief**: the single session you talk to. It finds the other sessions, starts and stops them, sends each request to the right one, and writes every hand-off into a ledger so its reports are based on files, not memory.

[![head-chief intro video](assets/head-chief-intro.gif)](assets/head-chief-intro.mp4)

*41-second intro. Click for the full-resolution MP4.*

## Quick start

```bash
# 1. Install the skills into your project (the CLI lets you pick which ones)
npx skills add duylongpro99/head-chief
```

```text
# 2. In any Claude Code session in that project
/head-chief
```

That session is now the chief. Talk to it in plain language:

```text
what is everyone working on?
start a session to fix the 500 on /login
ask api-tests which branch it is on
stop the docs session, it's done
```

Spawning and stopping sessions needs [Herdr](#requirements) (`HERDR_ENV=1`). Without it, the chief still coordinates sessions that are already running.

## How it works

Every request you send the chief is sorted into one of three lanes:

| Lane | Example | What the chief does |
| --- | --- | --- |
| **CHIEF** | "what is everyone doing?" | Answers directly from the ledger and the live session list (`ListAgents`). |
| **MAIN** | "fix the 500 on /login" | Writes a request log, then forwards the task into a staff session's main context. |
| **SIDECAR** | "which branch is api-tests on?" | Sends a small lookup that keeps the staff session's context footprint low. |

The chief keeps its state in `.orchestrator/` at the project root, created on first run:

```text
.orchestrator/
├── system-prompt.md                  # chief persona, editable per project
├── tracks/
│   ├── INDEX.md                      # fleet board, regenerated on every track write
│   └── <session>/status.md           # mission and timeline of each staff session
└── logs/
    └── <session>/<YYYYMMDD>-<HHMM>Z-<slug>.md   # one file per chief → staff request
```

A staff session writes its answer into the log and ends it with `**STATUS:** DONE` or `BLOCKED`. The chief reports from that log body, and it checks before any action that touches shared state and cannot be undone.

**The chief never writes application code.** Coding always goes to a staff session; the chief only routes, tracks and reports.

## The skills

This repo ships five skills that work together. Install only what you need.

| Skill | Use it when you want to… |
| --- | --- |
| **`head-chief`** | Make one session the orchestrator: session roster, routing, the `.orchestrator/` ledger, consolidated reports, and discussion mode. |
| **`managed-session`** | Start or stop a Claude Code session as a Herdr pane (default, needs `HERDR_ENV=1`) or a herdr core terminal (`--hc`, needs `hc`). Each session's auto-compact window defaults to 400k tokens (`--compact-window` to change it). The chief uses this to spawn staff. |
| **`pr-review-loop`** | Have a separate session review your GitHub PRs and loop review → verify/fix → re-review until approved. Cook mode (run by the implementer), reviewer mode (finds and wakes or restores the implementer session) and `--review-only`. |
| **`envoy-peer`** | Hand one task with acceptance criteria to a different agent CLI (codex, grok, omp, agy, …) in its own Herdr pane, have an independent reviewer pane check it, and loop fix → re-review until accepted. Only the status, a short summary and file paths come back. |
| **`roadmap-supervisor`** | Drive a roadmap of milestones, or one plan of phases, to completion through single-purpose worker sessions (plan, cook, review, debug), each with a brief file. Relays your decisions through a ledger in `~/supervisor` and closes every session it opened. Needs `managed-session`. |

The repo also holds two standalone skills outside the orchestration group: `ak-proposal-review` (review a proposal as a local HTML draft with per-section feedback) and `ui-paper-pencil-design` (the paper-and-pencil page style used in the intro video).

## Usage

### Discussion mode

Convene a panel of peer sessions, each with a distinct lens, that argue in barriered rounds and converge on one consensus report:

```text
/head-chief --discussion "<topic>" [--lenses ...] [--roster N] [--scribe <vibe>] [--rounds 3] [--out ...]
```

### Hand a task to another agent kind

```text
/envoy-peer [--kind codex] [--reviewer claude] [--max-rounds 3] "<task>"
/envoy-peer --cleanup --all
```

The session writes a brief with acceptance criteria, opens the envoy in a Herdr pane next to it, and has a reviewer pane (by default the controller's own kind) check the result against that brief. The envoy runs with full permission in the same working tree, so do not edit the tree while a run is going. Each CLI keeps its own credentials: the skill never reads, stores or types them, and a login screen is left for you to finish in the pane. Runs live under `.envoy/runs/` at the git root; the folder ignores itself.

### Review PRs in a loop

```text
/pr-review-loop OWNER/REPO#12 OWNER/REPO#13
/pr-review-loop --review-only OWNER/REPO#12
```

### Supervise a roadmap

Ask a session to "supervise the roadmap" (or run `/roadmap-supervisor`). It shapes the work, opens one worker session per job, picks the skill for each role, and asks you only when a decision is genuinely yours.

Every question it asks you also lands in a ledger file in one shared folder, `~/supervisor/<project>--<session>.md`, so you can answer all running supervisors from one place: write after `Answer:` and save, or type `D3: A` in the supervisor's chat. The supervisor reads only the newly answered items, moves each recorded answer into the project's `pending-decisions.archive.md`, and on stopping moves the ledger back to the project as `pending-decisions.final.md`. The folder needs per-repo access, which `install.sh --project` grants (see [Install options](#install-options)). The ledger commands (`init`, `add`, `answers`, `record`, `seen`, `list`, `close`) are in [`pending-decisions-format.md`](skills/roadmap-supervisor/references/pending-decisions-format.md).

## Requirements

| Requirement | Needed for | Notes |
| --- | --- | --- |
| **Cross-session messaging** (`ListAgents` / `SendMessage`) | Everything | The feature `head-chief` is built on. Needs Claude Code ≥ 2.1.224 (macOS/Linux). If `ListAgents` is unavailable, the skill tells you and stops. |
| **Ledger** at `<project-root>/.orchestrator/` | State | Created automatically by `head-chief`'s `init_ledger.py` on first run (idempotent). |
| **Herdr** (`HERDR_ENV=1`) | Spawning / stopping sessions | Needed by `managed-session`, and so by `roadmap-supervisor`. Without it the chief still manages already-running sessions; it just can't create or stop them itself. |
| **Herdr**, `jq`, `git` | `envoy-peer` | Herdr ≥ 0.8.0 with `HERDR_ENV=1`; there is no fallback outside Herdr. Bash 3.2 or later. |
| **Agent CLIs** (codex, grok, omp, agy, claude) | `envoy-peer` | Install and log in to the kinds you want to use. Launch flags for each kind live in `skills/envoy-peer/references/kinds.json`; a kind without a verified row is not offered. |

## Install options

The skills are distributed as [Agent Skills](https://skills.sh), so the `skills` CLI installs them into Claude Code or any of the 70+ supported agents.

```bash
npx skills add duylongpro99/head-chief --all                         # everything, non-interactive
npx skills add duylongpro99/head-chief --skill head-chief            # just the orchestrator
npx skills add duylongpro99/head-chief --skill envoy-peer            # just the cross-kind envoy
npx skills add duylongpro99/head-chief --all -g -a claude-code       # global, Claude Code only
npx skills use duylongpro99/head-chief --skill head-chief | claude   # preview without installing
```

Installed skills live at `.claude/skills/<name>/` (project scope) or `~/.claude/skills/<name>/` (global, with `-g`).

### Install, update and uninstall across repos

There are three ways to install a skill into a project. Pick one per project and skill, because a symlink and a copy cannot share the same folder.

| Method | Install | How updates arrive | Update | Uninstall |
| --- | --- | --- | --- | --- |
| Symlink per project | From the consumer repo root: `~/personal/head-chief/install.sh --project --skill <name>` | The link follows the checkout's current HEAD | `git -C ~/personal/head-chief pull` updates every linked repo at once | `~/personal/head-chief/install.sh --uninstall --project --skill <name>` |
| Symlink global | `~/personal/head-chief/install.sh --skill <name>` (links into `~/.claude/skills`) | Same as above | Same as above | `~/personal/head-chief/install.sh --uninstall --skill <name>` |
| `npx skills` copy | `npx skills add duylongpro99/head-chief --skill <name>` (add `-g` for global) | Only after a push to the default branch on GitHub | `npx skills update <names>` | `npx skills remove <names>` |

- **Symlinks follow HEAD.** Never switch branches in `~/personal/head-chief` while a supervisor or another session uses a linked skill: it changes the skill under every running consumer. Develop in a worktree (`git worktree add ../head-chief-<topic> -b <branch> main`), and pull `main` only when no supervisor is mid-run.
- **Dependencies.** `roadmap-supervisor` needs `managed-session`. It declares this in its frontmatter (`metadata.requires`), and `install.sh` links the dependency too (`adding dependency managed-session (required by roadmap-supervisor)`). If the project already has `managed-session` in any form (a copy, or a link to another clone), it is left as is, even with `--force`; name it with `--skill managed-session` to relink it. `install.sh --uninstall` removes only the skills you name. `npx skills` does not read `requires`, so name both: `npx skills add duylongpro99/head-chief --skill roadmap-supervisor --skill managed-session`.
- **Find every consumer.** Symlinks into this checkout, or into any other clone whose path ends in `head-chief`:

  ```bash
  find ~ -maxdepth 6 -path '*/.claude/skills/*' -type l -lname '*head-chief/skills/*' \
    -exec sh -c 'printf "%s -> %s\n" "$1" "$(readlink "$1")"' _ {} \;
  ```

  `npx skills` copies are recorded in each project's `skills-lock.json`: run `grep -l head-chief **/skills-lock.json` (zsh, or bash with `shopt -s globstar`) from a parent folder.
- **Relink a link that points into another clone.** From the consumer repo root, run `~/personal/head-chief/install.sh --project --force --skill <name>`. `--force` replaces only symlinks, never a real folder.

### Access to the shared supervisor folder

Installing `roadmap-supervisor` with `--project` also lets that repo's Claude sessions use the shared folder `~/supervisor` (override with `SUPERVISOR_HOME=/abs/path`). It:

- creates the folder;
- adds it to `<repo>/.claude/settings.local.json` under `permissions.additionalDirectories`, keeping other keys and the file's mode, and saving the previous file as `settings.local.json.bak` when it changes;
- records the repo in `~/supervisor/.installs`.

This needs `jq`. Without it, `install.sh` exits 1 and prints the JSON to merge by hand. It refuses a repo where git does not ignore `.claude/settings.local.json` unless you pass `--force`. Only per-repo settings are written, never `~/.claude/settings.json`; a global or `--agents` install only prints a reminder. A Bash sandbox needs no extra entry, because it can write to every directory in `additionalDirectories`.

```bash
# from the consumer repo root
~/personal/head-chief/install.sh --project --skill roadmap-supervisor
# remove the grant and the registry line (the folder itself is never deleted)
~/personal/head-chief/install.sh --uninstall --project --skill roadmap-supervisor
# grant every registered repo again; a second run changes nothing
~/personal/head-chief/install.sh --sync-settings [--scan DIR ...] [--force] [--dry-run]
```

`--scan DIR` first registers every repo under `DIR` (up to 6 levels deep) whose `.claude/skills/roadmap-supervisor` links into this checkout. Repos that had the skill before this feature need one run:

```bash
~/personal/head-chief/install.sh --sync-settings --scan ~/personal
```

If a running session still cannot write the folder, run `/add-dir ~/supervisor` in it or restart it.

## Repository layout

Each skill lives under `skills/<name>/` with its own `SKILL.md`, so the `skills` CLI discovers each of them.

```text
skills.sh.json             # skills.sh grouping manifest
skills/
  head-chief/
    SKILL.md               # Orchestrator entry point + operating steps
    references/            # ledger-protocol.md, messaging-protocol.md, discussion-mode.md
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
  roadmap-supervisor/
    SKILL.md               # Supervisor flow: shape, start, briefs, monitoring, operator gate, cleanup
    references/            # brief-template, role-skill-map, monitoring-and-operator-gate, pending-decisions-format
    scripts/               # pending-watch.sh (no-model ledger watcher and writer) and its tests
  ak-proposal-review/      # Standalone: local HTML proposal review
  ui-paper-pencil-design/  # Standalone: paper-and-pencil page style
assets/                    # README intro video (MP4 + GIF preview)
video/                     # Remotion source of the intro video
install.sh                 # Symlink skills from this checkout into a host's skill folder
```

## Development

```bash
cd skills/head-chief
python3 scripts/init_ledger.py --test   # self-test the bootstrap + clock
python3 scripts/quick_validate.py        # structural validation (ownership, resources, templates, secret hygiene)
```

```bash
bash skills/roadmap-supervisor/scripts/tests/test-pending-watch.sh   # ledger watcher, stubbed herdr and terminal-notifier
bash tests/test-install.sh                                           # install.sh links and ~/supervisor grants, in a temp HOME
```

To try a skill from this checkout without publishing, link it into a host's skill folder:

```bash
./install.sh                    # ~/.claude/skills/envoy-peer -> skills/envoy-peer
./install.sh --project          # <git root>/.claude/skills; refused unless git ignores the link
./install.sh --uninstall        # remove only links that point into this checkout
./install.sh --help             # other destinations, --skill, --force, --dry-run
```

The links follow this checkout's current HEAD: switching branches here changes the skill everywhere it is linked.

### Rebuild the intro video

The video is a [Remotion](https://www.remotion.dev) project in `video/` (1920×1080, 30 fps).

```bash
cd video
npm install
npm run studio    # live preview in the browser
npm run render      # writes ../assets/head-chief-intro.mp4
npm run render:gif  # regenerates the README GIF from that MP4 (needs ffmpeg)
```

## Publishing updates

`npx skills` resolves from GitHub, so publishing an update is just pushing to the default branch. Consumers pull the latest with:

```bash
npx skills update head-chief managed-session pr-review-loop envoy-peer roadmap-supervisor
```
