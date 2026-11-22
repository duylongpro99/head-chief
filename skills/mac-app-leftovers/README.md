# mac-app-leftovers

Find and clean the files that uninstalled macOS apps and tools leave behind: preferences,
containers, caches, Application Support folders, LaunchAgents whose program is gone, and
Login Items that point to a missing app. Sizes are shown per app.

It works two ways:

- **As an agent skill.** Ask Claude something like "find what uninstalled apps left behind"
  or run `/mac-app-leftovers`. Claude runs the same script, then helps you decide which
  `review` items are safe to remove.
- **As a standalone script**, described below. No agent and no tokens are needed.

## Run it standalone with uv

The script uses only the Python standard library and declares itself as a
[uv script](https://docs.astral.sh/uv/guides/scripts/), so `uv` runs it in an isolated
environment with nothing to install. It works on macOS only.

```bash
SCRIPT=~/personal/head-chief/skills/mac-app-leftovers/scripts/leftovers.py

uv run "$SCRIPT" scan                         # list leftovers with sizes (read-only)
uv run "$SCRIPT" scan --min-kb 1024           # hide entries smaller than 1 MB
uv run "$SCRIPT" scan --json                  # machine-readable output

uv run "$SCRIPT" clean                        # dry run: show what would be moved
uv run "$SCRIPT" clean --yes                  # move the high-confidence leftovers to the Trash
uv run "$SCRIPT" clean --app firestore --yes  # only one app, including its review items
uv run "$SCRIPT" clean --include-review --yes # also move every review item
```

To type less, add an alias to `~/.zshrc`:

```bash
echo 'alias leftovers="uv run ~/personal/head-chief/skills/mac-app-leftovers/scripts/leftovers.py"' >> ~/.zshrc && source ~/.zshrc
```

Then run `leftovers scan` or `leftovers clean --yes`.

Without uv, `python3 scripts/leftovers.py scan` works the same way (Python 3.9 or newer).

## Reading the results

Each app group has a confidence level:

- `high`: the group has an entry that only real apps create (Containers, Group Containers,
  Saved Application State, HTTPStorages, WebKit) or a LaunchAgent whose program is gone.
  `clean` moves these by default.
- `review`: matched by folder name only (Caches, Application Support, Logs, home
  dotfolders) or by a preferences file alone. These can belong to a tool you still use, or
  to an installed app with an unusual folder name. Check them before cleaning; `clean`
  skips them unless you pass `--include-review` or name the app with `--app`.

`clean` moves items to the Trash, so you can restore them until you empty it. It only
touches items inside `~/Library/<folder>/` and top-level `~/.dotfolders`.

## Troubleshooting

- **`Operation not permitted` on Containers or Group Containers.** macOS protects these
  folders. The script falls back to Finder automatically. If that also fails, grant Full
  Disk Access to your terminal app (System Settings > Privacy & Security > Full Disk
  Access), quit and reopen the terminal, and run `clean` again. Dragging the listed folders
  to the Trash in Finder also works.
- **A removed app still shows in Login Items.** `scan` lists these under "Login items
  pointing to apps that no longer exist". Fix them with `sudo sfltool resetbtm`, then
  restart. This resets every background item, so other apps may ask for permission again.

## Tests

```bash
cd ~/personal/head-chief/skills/mac-app-leftovers
uv run python -m unittest discover -s scripts/tests
```
