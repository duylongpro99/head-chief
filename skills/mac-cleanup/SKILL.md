---
name: mac-cleanup
description: "Audit what fills this Mac's disk and clean the safe parts: package-manager caches (npm, yarn, pnpm, go, bun, uv, pip, brew), unused Docker images and anonymous volumes, and build artifacts (node_modules, target, .next, .venv, .turbo) in projects with no recent commits. Use when the user asks why the disk or System Data is so full, what can be deleted, or to free up space; Vietnamese asks like 'kiểm tra dung lượng ổ đĩa', 'dọn ổ cứng', 'sao system storage nhiều vậy' also apply. Not for leftovers of uninstalled apps (use mac-app-leftovers) or uninstalling apps."
compatibility: "macOS only; bash 3.2+, optional docker/xcrun/npm/yarn/pnpm/go/bun/uv/pip3/brew."
---

# Mac Cleanup

One script, two modes: **report** shows where the space goes; **clean** removes only things
that are rebuilt or re-downloaded on demand. The quality bar is never deleting data the user
cannot get back.

## How to work

Run `scripts/mac-cleanup` from this skill folder (also on PATH as `mac-cleanup` if linked).
A full report takes 2-3 minutes because it runs `du` over home and /Applications; run it
with a long timeout.

- **report**: `scripts/mac-cleanup` (add `--days N` to change the stale threshold, default
  90 days since the project's last commit; `--root DIR` to scan other project folders).
  Read-only. Summarize the biggest items for the user, grouped as: safe to clean, needs the
  user's decision, and cannot be cleaned (system).
- **clean**: only after the user agrees, run `scripts/mac-cleanup --clean --yes`. It prunes
  package caches, Docker (images, anonymous volumes, build cache) and the stale build
  artifacts listed in the report, then prints the space freed.

Project folders come from `~/.config/mac-cleanup.conf` (one path per line), else whichever of
`~/personal ~/projects ~/code ~/dev ~/src` exist.

## Never delete automatically

These are listed in the report only. Explain them and let the user decide:

- Docker **named** volumes: local database data. `docker volume prune` skips them; `-a` does not.
- iOS Simulator runtimes (`xcrun simctl runtime delete <UUID>`): check `simctl list devices`
  to see which simulators use each one before suggesting a delete.
- Claude Desktop `vm_bundles` (~9 GB): the sandbox VM; re-downloaded when needed.
- Browser and app caches (Chrome, Arc, Spotify): clear them from each app's settings with the
  app quit.
- Applications, including large games: show the last-used date and ask.

## Reading the numbers

- `docker system df` can report volume sizes far beyond the disk (sparse files). The real
  footprint is `du -h ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`.
  Its `ls` size (often 60 GB) is the ceiling, not usage.
- `du` over the Data volume usually lands tens of GB under `df`: the rest is SIP-protected or
  purgeable system data that cannot be cleaned by hand. Say so rather than hunting for it.

## Done when

- report: the user sees the biggest consumers, what is safe to clean, and what needs a decision.
- clean: the run prints `Thu hồi được: X GB` and the new free space; tell the user the number.
