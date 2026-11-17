# Code review: feat/roadmap-supervisor-pending-ledger

Date: 2026-11-17. Reviewer: independent code-reviewer agent, read-only. It reproduced each
high and medium finding with a stub `herdr` on macOS `/bin/bash` 3.2.57.

| ID | Finding | Resolution |
|---|---|---|
| H1 | After a `user-edit` exit with nothing to rewrite (a `Seen: [x]` the operator set), the restarted watcher exits again every ~10 s | Docs: always run `synced` before restarting (`d119d6d`) |
| H2 | `synced` could absorb an answer the operator saved just before a supervisor write | `synced` now lists unrecorded file answers; docs say to record them at once; test 8 (`d119d6d`) |
| H3 | A stale pid could make `stop` kill an unrelated process and make `watch` refuse to start | `pid_alive` checks that the command is pending-watch; test 9 (`d119d6d`) |
| M1 | `install.sh` failed when a dependency was already present as a copy or a link elsewhere, and `--force` relinked it | A dependency nobody named is left as is (`d3e7a65`); phase 7 now names `managed-session` for translate-side |
| M2 | Recording an answer with Edit cannot run `synced` in the same call | Docs: change the ledger only from Bash (`d119d6d`) |
| L1 | CRLF ledgers parsed as malformed | `\r` stripped; test 10 (`d119d6d`) |
| L2 | `pgrep -f pending-watch` matches other supervisors' watchers | Docs scope it to the folder (`d119d6d`) |
| L3 | A file missing mid-save could end the watcher with exit 1 | Hash and parse treat it as missing (`d119d6d`) |
| L4 | Possible orphaned watcher if the Claude session dies without stopping background tasks | Not verified; left open |
| L5 | `requires_of` reads only the inline `requires: a, b` form | Accepted: the only frontmatter uses that form |

Checked and fine: docs match the parser; bash 3.2 constructs; EXIT trap on user-edit, TERM
and HUP; real `herdr` output is raw UTF-8.

Verification after fixes: tests 10/10 on `/bin/bash`, shellcheck clean, and install.sh
checked for a dependency present as a copy, as a link elsewhere (with `--force`), when named
explicitly, on a fresh install, and for the default `envoy-peer` dry-run.
