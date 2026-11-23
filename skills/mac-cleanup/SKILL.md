---
name: mac-cleanup
description: "Audit what fills this Mac's disk and clean it by group: package-manager caches (npm, yarn, pnpm, go, bun, uv, pip, brew), unused Docker images and anonymous volumes, and build artifacts (node_modules, target, .next, .venv, .turbo) in projects with no recent commits by default; Docker named volumes, iOS Simulator runtimes, the Claude Desktop VM and browser/app caches only when opted in. Prints a ready-to-paste delete command for everything it does not clean. Use when the user asks why the disk or System Data is so full, what can be deleted, or to free up space; Vietnamese asks like 'kiểm tra dung lượng ổ đĩa', 'dọn ổ cứng', 'sao system storage nhiều vậy' also apply. Not for leftovers of uninstalled apps (use mac-app-leftovers) or uninstalling apps."
compatibility: "macOS only; bash 3.2+, python3 for the simulator table; optional docker/xcrun/npm/yarn/pnpm/go/bun/uv/pip3/brew."
---

# Mac Cleanup

One script, two modes: **report** shows where the space goes and prints a delete command
for every item; **clean** removes only the groups that are selected. The quality bar is
never deleting data the user did not choose to lose.

## Groups

| Group | Default | What `--clean` removes |
|---|---|---|
| `caches` | on | npm, yarn, pnpm, go, bun, uv, pip, brew caches |
| `docker` | on | unused images, anonymous volumes, build cache |
| `artifacts` | on | `node_modules`, `target`, `.next`, `.venv`, `venv`, `.turbo` in projects with no commit in `--days` (default 90) |
| `docker-volumes` | off | named volumes no container uses (local DB data is lost) |
| `simulators` | off | `unavailable` simulators and runtimes no simulator uses |
| `claude-vm` | off | Claude Desktop `vm_bundles`; skipped while Claude runs |
| `app-caches` | off | Chrome, Arc, Firefox, Spotify, VSCode updater caches; skips apps that are running |

Applications are never deleted; the report suggests `mv … ~/.Trash/` for apps unused longer
than `--days`.

## How to work

Run `scripts/mac-cleanup` from this skill folder (also on PATH as `mac-cleanup` if linked).
A full report takes 2-3 minutes because it runs `du` over home and /Applications; run it
with a long timeout.

- **report**: `scripts/mac-cleanup`. Read-only. Summarize the biggest items as: cleaned by
  default, needs the user's decision (opt-in groups, apps), and cannot be cleaned (system).
  Quote the suggested commands from the output; they contain the real UUIDs, volume names
  and paths and paste straight into zsh.
- **clean**: only after the user agrees, run `scripts/mac-cleanup --clean --yes` with the
  groups they chose: `--only g1,g2` (exact set), `--add g1,g2` (on top of the defaults),
  `--skip g1,g2`. Add an opt-in group only when the user named it or agreed to it.
- For a runtime or volume that is still in use, the `simulators` / `docker-volumes` groups do
  not touch it; give the user the matching suggested command instead.

## Configuration

`~/.config/mac-cleanup.conf` (or `$XDG_CONFIG_HOME/mac-cleanup.conf`); command-line options win.

```text
~/personal                     # a bare path, or `root = <path>`: project folder to scan
clean = caches artifacts claude-vm   # replaces the default group list
skip  = docker                 # never clean these groups
days  = 60                     # stale threshold
```

Without project roots, the script scans whichever of `~/personal ~/projects ~/code ~/dev ~/src` exist.

## Reading the numbers

- `docker system df` can report volume sizes far beyond the disk (sparse files). The real
  footprint is `du -h ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`.
  Its `ls` size (often 60 GB) is the ceiling, not usage.
- An app last-used date of "chưa ghi nhận" (not recorded) does not mean unused: games and
  tools started through their own launcher often have none.
- `du` over the Data volume usually lands tens of GB under `df`: the rest is SIP-protected or
  purgeable system data that cannot be cleaned by hand. Say so rather than hunting for it.

## Done when

- report: the user sees the biggest consumers, which groups `--clean` will run, and a delete
  command for everything else.
- clean: the run prints `Thu hồi được: X GB` and the new free space; tell the user the number.
