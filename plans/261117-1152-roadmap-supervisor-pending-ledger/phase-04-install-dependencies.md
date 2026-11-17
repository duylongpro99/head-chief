---
phase: 4
title: install.sh dependencies and install guide
status: completed
effort: 1.5h
depends_on: [1]
---

# Phase 4: install.sh dependencies and install guide

## Context

`install.sh` links the skills named with `--skill` (default `envoy-peer`) into a project,
global or custom folder, and refuses a project link that git does not ignore. It has no
notion of dependencies, so `--skill roadmap-supervisor` alone would leave the supervisor
without `managed-session`. The README's install section covers `npx skills add`, but has no
per-method guide for updating or uninstalling. Consumers today use symlinks into
`~/personal/head-chief`, plus one into a stale clone (`general-cc-kit/skills/head-chief`,
992308b).

## Requirements

1. Declare the dependency in `skills/roadmap-supervisor/SKILL.md` frontmatter:
   ```yaml
   metadata:
     requires: managed-session
   ```
   First confirm that `npx skills` still lists the skill with this key. Run
   `npx skills add <worktree path> --list` (or the CLI's equivalent dry listing) and record the
   output in the commit body. If it breaks, use the fallback `# requires: managed-session` comment
   line instead, and say so in the phase report.
2. `install.sh`: after parsing, expand the skill list by each skill's `requires`, one level,
   space- or comma-separated, de-duplicated, in order. A missing dependency is an error naming
   both skills. Print `adding dependency managed-session (required by roadmap-supervisor)`.
   `--uninstall` does not expand dependencies. Update the usage header comment.
3. README: add an "Install, update and uninstall across repos" subsection with a table of the
   three methods. For each method give the install command, how updates arrive, the update
   command and the uninstall command:
   - symlink per project: updates follow the checkout's HEAD; `git -C ~/personal/head-chief pull` updates every linked repo; never switch branches in that checkout while a supervisor runs; uninstall with `./install.sh --uninstall --project --skill …`;
   - symlink global;
   - `npx skills` copy: `npx skills update <names>` after a push to the default branch.

   Also include:
   - one documented command that finds consumers: `find ~ -path '*/.claude/skills/*' -maxdepth 6 -type l -lname '*head-chief/skills/*' -exec sh -c 'printf "%s -> %s\n" "$1" "$(readlink "$1")"' _ {} \;`, plus `grep -l head-chief **/skills-lock.json` for npx copies;
   - how to relink a link that points into another clone: `./install.sh --project --force --skill <name>`, run from the consumer repo;
   - a note that roadmap-supervisor pulls in managed-session.

## Files

- Modify: `install.sh`, `README.md`, `skills/roadmap-supervisor/SKILL.md` (frontmatter only)

## Steps

1. Run the `npx skills` listing check for the frontmatter key.
2. Implement dependency expansion and update the usage header.
3. Write the README subsection.
4. Commit `feat(install): link skill dependencies declared in metadata.requires`, then `docs: guide for installing and updating skills across repos`.

## Validation

- `./install.sh --dry-run --target "$(mktemp -d)" --skill roadmap-supervisor` prints links for both `roadmap-supervisor` and `managed-session`.
- `./install.sh --dry-run --uninstall --target <same dir> --skill roadmap-supervisor` names only roadmap-supervisor.
- `./install.sh --dry-run --skill envoy-peer` behaves as before (no extra skills).
- A requires entry naming a missing skill (temporary edit in a temp copy) exits 1 with both names.
- `bash -n install.sh` passes, and so does `shellcheck install.sh` if it is installed.

## Risk and rollback

Existing calls without `requires` are unchanged. Rollback: revert the two commits.
