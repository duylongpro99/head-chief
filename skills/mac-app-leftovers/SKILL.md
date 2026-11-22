---
name: mac-app-leftovers
description: "Find and clean files and folders left on this Mac by apps and tools that were uninstalled (preferences, containers, caches, Application Support, dead LaunchAgents, stale login items), with sizes per app. Use when the user asks what an uninstalled app left behind, why a removed app still shows in Login Items, or wants that leftover data cleaned; Vietnamese asks like 'tìm file sót của app đã gỡ', 'dọn rác app đã xoá' also apply. Not for uninstalling an app that is still installed, general disk-space analysis, or clearing caches of tools still in use."
compatibility: "macOS only; python3 standard library."
---

# Mac App Leftovers

Two modes over one scanner: **scan** shows what uninstalled apps left behind and how much
space each takes; **clean** moves the selected leftovers to the Trash. The user owns this
Mac; the quality bar is no false deletions of data that belongs to an app still installed.

## How to work

Run the bundled script with `python3` from this skill folder.

- **scan**: `python3 scripts/leftovers.py scan` (add `--json` for machine-readable output,
  `--min-kb 1024` to hide tiny entries). Read-only. Present the result to the user grouped by
  app with sizes, biggest first, and say which groups are `high` and which are `review`.
- **clean**: always run the dry run first, `python3 scripts/leftovers.py clean`, and show the
  list. Only after the user confirms, run it again with `--yes`. Narrow with
  `--app <name>` (repeatable; an explicitly named app includes its review items) or widen
  with `--include-review`.

Cleaning moves items to the Trash, so the user can restore them until they empty it. The
script refuses paths outside `~/Library/<dir>/<item>` and top-level `~/.dotfolders`.

## Confidence, and why it matters

- `high`: the group has an entry only apps create (Containers, Group Containers, Saved
  Application State, HTTPStorages, WebKit) or a LaunchAgent whose program is gone. Safe to
  clean by default.
- `review`: matched only by name (Caches, Application Support, Logs, home dotfolders) or a
  preferences file alone. These are often SDK caches, CLI tools, emulators or folders of an
  installed app with an unusual name (for example `~/Library/Logs/TFT` belongs to the
  installed Teamfight Tactics). Before suggesting a review item for cleaning, check whether
  the user still uses the tool it belongs to; when unsure, ask instead of cleaning.

Known false-positive shapes the script already handles: helper bundle IDs of installed apps
(`com.spotify.client-launcher`), renamed bundles (`com.microsoft.teams` vs installed
`teams2`), vendor-shared group containers (`UBF8T346G9.com.microsoft.oneauth`), vendor data
folders (`ZaloData`, `JetBrains`), and developer caches of tools still in use (Playwright,
Homebrew, go-build, TypeScript). When a new false positive appears, add it to the matching
rule or set in the script and a case to `scripts/tests/test_leftovers.py`.

## Known failure modes

- `Operation not permitted` on Containers / Group Containers: macOS protects them. The
  script falls back to Finder; if that also fails, tell the user to grant Full Disk Access
  to their terminal app (System Settings > Privacy & Security), quit and reopen it, then
  clean again, or drag the listed folders to the Trash in Finder.
- Stale Login Items: scan lists background items whose app is gone. The only fix is
  `sudo sfltool resetbtm` plus a restart, which resets every background item (other apps
  may ask for permission again). It needs sudo and a restart, so give the user the command
  to run.
- When giving the user shell commands to paste, keep each command on one line; multi-line
  commands with `\` lose their first line when copied partially and zsh then tries to run
  a path as a command (`zsh: permission denied: <path>`).

## Done when

- scan: the user sees every group with size and confidence, plus any stale login items.
- clean: the `--yes` run reports what moved and lists anything not moved with the reason;
  a follow-up scan no longer shows the cleaned groups. Remind the user to empty the Trash.

## Resources

- `scripts/leftovers.py`: scanner and cleaner, `scan` / `clean` subcommands as above.
- `scripts/tests/test_leftovers.py`: classification tests; run
  `python3 -m unittest discover -s scripts/tests` from the skill folder after changing rules.
