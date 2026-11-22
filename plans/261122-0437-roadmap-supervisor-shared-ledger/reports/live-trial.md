# Live trial: shared ~/supervisor ledger under Herdr

Date: 2026-11-22. Code: branch `feat/roadmap-supervisor-shared-ledger` in the worktree
`~/personal/head-chief-wt-shared-ledger`. Supervisors A and B were real Sonnet 5.5 Claude Code
sessions under Herdr, started with `managed-session/scripts/create-session.sh`.

## Result

All nine steps passed. Both unverified items in the plan are closed: a running session picks up a
new `additionalDirectories` entry with no restart, and the Bash sandbox needs no extra entry.
Nothing from the trial is left running or installed.

## Steps

| # | Step | Result |
|---|---|---|
| 1 | Install into scratch repos `tmp-supervisor-trial-{a,b}` (and `c` for step 7) from the worktree | Pass. Each `settings.local.json` listed `~/supervisor`, and `~/supervisor/.installs` listed the repos. The links pointed at the worktree. |
| 2 | Start supervisors A and B through Start up to the watcher | Pass. `~/supervisor` held `tmp-supervisor-trial-a--trial-a-sup.md` and `…-b--trial-b-sup.md`, each with the project, path, session, Herdr tab and pane, start time and archive path. |
| 3 | A adds two items and B adds one; answer A's D1 in the editor | Pass. The badges read `trial-a ⏳2` and `trial-b ⏳1`. The watcher exited with `user-edit`. A ran `answers`, which printed only D1, and did not Read the ledger. Then it ran `record D1 file`: the item moved to the archive and the restarted watcher did not wake again. Later, D2 was answered in the file and recorded the same way. |
| 4 | Answer B's item in chat with `D1: A` | Pass. B ran `record D1 chat "A"`, and the archive entry reads `(chat) A`. |
| 5 | Grant takes effect without a restart | Yes. In a running session in acceptEdits mode, a Write to `~/supervisor` went through without a prompt right after `install.sh` changed `settings.local.json`, and a control directory outside the grant was prompted. The `/add-dir` fallback is not needed, and the SKILL.md wording stays. |
| 6 | Notification click opens the live file | Pass, checked from the arguments rather than a physical click. With a stub `terminal-notifier` on PATH, a watcher on a session named `note chk` passed `-open file://…/sup--note%20chk.md`, and that URL decodes to the existing shared ledger, space included. |
| 7 | Migration from the old layout with a watcher running | Pass. An old-layout `pending-decisions.md` held D1 ANSWERED, D2 OPEN unseen and D3 OPEN answered, with a watcher from the `main` script running. `init` stopped that watcher (pid 53362). D2 and D3 went to the shared file and D1 went to the archive, and the old file was kept as `pending-decisions.md.migrated`. `init` named D3 as waiting, `answers` printed only D3, and `list` showed D2 unseen and D3 answered. |
| 8 | `close` all supervisors | Pass. A and B ran `close` when asked in their sessions, and C was closed by hand. Afterwards `ls -A ~/supervisor` showed only `.installs`. Each project held `pending-decisions.final.md` and `pending-decisions.archive.md`, and C's final ledger kept D2 and D3. |
| 9 | Clean up | Pass. Both sessions were stopped with `stop-session.sh`, and `pgrep -f pending-watch` found nothing. `install.sh --uninstall --project` revoked the grant and removed the registry line in all three repos, which leaves `.installs` empty. The scratch repos were deleted. |

## Observations

- Supervisor A first called `record D1 file "A, Postgres"`. The script refused, because `file` takes no text, and the supervisor corrected itself on the next call. The refusal message is enough; no change was made.
- Live ledgers are created with mode 0600 because they are written through `mktemp`. Only the operator reads them, so this stays.
- After recording its last answer, supervisor A left the watcher stopped because nothing was pending. The reference already says to start the watcher "whenever it is not running", so this was the model's own choice. It would have to start the watcher before its next `add`.
- After `close`, both supervisors left the watcher row in `sessions.md` marked running, because they had been told to start no new work. This is outside the ledger change.
- The first stub-notifier check hung because `add` reads the item from stdin. That was a mistake in the test call, not in the script.

## Doc changes from the trial

None were needed beyond the review fixes already committed. Those fixes added the `Folder:` header line, re-running `init` after `close`, and the `init`/`close` entries in the SKILL.md command list.
