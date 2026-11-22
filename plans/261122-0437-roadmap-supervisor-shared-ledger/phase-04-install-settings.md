---
title: "Phase 4: install.sh grants ~/supervisor per repo"
status: done
---

# Phase 4: install.sh grants ~/supervisor per repo

## Overview

Priority P1, 3h. No dependency on phases 1–3; it may run in parallel. Installing
roadmap-supervisor into a repo gives that repo's Claude sessions access to `~/supervisor`. A
registry and a one-time scan update repos that already have the skill.

## Requirements

- Trigger: `--project` with `roadmap-supervisor` among the linked skills. With a global or
  `--agents` target, print one line explaining that access is granted per repo with `--project`.
- Grant, for a repo root `R`:
  - `mkdir -p "$SUPERVISOR_HOME"` (default `$HOME/supervisor`);
  - in `R/.claude/settings.local.json`, create `{}` when missing, then add the absolute
    `$SUPERVISOR_HOME` to `.permissions.additionalDirectories` with `jq`, without duplicates and
    keeping every other key;
  - only when the content changes, copy the old file to `settings.local.json.bak` first;
  - refuse when git does not ignore `settings.local.json` (`--force` overrides), the same rule as the skill link;
  - add `R` to `$SUPERVISOR_HOME/.installs` (one absolute path per line, unique).
- `--sync-settings [--scan DIR ...]`:
  - `--scan` finds `.claude/skills/roadmap-supervisor` symlinks under DIR
    (`find -maxdepth 6`) whose target resolves into this checkout's `skills/roadmap-supervisor`, and
    adds their git roots to the registry;
  - then apply the grant to every registry entry; a missing repo gets a warning and is skipped, not removed;
  - a second run changes no file.
- `--uninstall --project --skill roadmap-supervisor`: remove the entry from
  `additionalDirectories`, delete the key when the list becomes empty, remove `R` from the
  registry, and never delete `~/supervisor`.
- Without `jq`: exit 1 and print the exact JSON to paste. Never edit JSON with `sed`.
- `--dry-run` prints every action and changes nothing.
- Check the current Claude Code settings docs (via `claude-code-guide` or the docs site) for whether
  `additionalDirectories` covers Bash sandbox writes. If it does not, also add the sandbox write
  entry, but only when that repo's settings enable the sandbox. Record the finding in the phase report.

## Implementation Steps

1. Add `grant_supervisor_dir <root>`, `revoke_supervisor_dir <root>`, `registry_add` and `registry_remove`.
2. Hook them into the existing project link and uninstall paths, and add the `--sync-settings` and `--scan` parsing.
3. Update the usage header.
4. New `tests/test-install.sh` (temp `HOME`, temp git repos with `.claude/` ignored, PATH unchanged):
   - install adds the entry and the registry line; a second install changes nothing (hash);
   - existing keys in `settings.local.json` survive; the `.bak` holds the old content;
   - a repo where `settings.local.json` is not ignored is refused without `--force`;
   - `--sync-settings --scan` finds a pre-existing link and grants it; a second run makes no change;
   - uninstall removes only the entry and the registry line;
   - `--dry-run` changes nothing;
   - a missing `jq` (PATH without it) exits 1 with the paste line.
5. README install section: the new flags and the one-time command
   `~/personal/head-chief/install.sh --sync-settings --scan ~/personal`.

## Todo

- [x] grant / revoke / registry helpers
- [x] --sync-settings, --scan, uninstall path
- [x] tests/test-install.sh passes
- [x] README install section; sandbox finding recorded

## Success Criteria

- `bash tests/test-install.sh` passes, and the idempotency checks compare file hashes.

## Risk

- Clobbering a user's settings file: write through `jq` to a temp file, then `mv`, with a `.bak` on every change.
- `--scan` over a large tree: bounded by `-maxdepth 6` and only checks symlinks named `roadmap-supervisor`.
