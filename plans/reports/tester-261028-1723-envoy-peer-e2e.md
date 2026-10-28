# E2E test report: envoy-peer

Date: 2026-10-28. Plan: `plans/261028-0731-envoy-peer-skill/` (phase 4).
Controller: Claude Code in Herdr 0.8.0, pane `wC:p8B` (kind `claude`). macOS, bash 3.2.57.
Sandbox: a throwaway git repo in the session scratchpad (`greet.sh` printing the wrong text, a red `test.sh`, commit `init` `5e22f21`, plus a modified `README.md` and an untracked `notes.txt` outside scope). Every test ran with `XDG_CONFIG_HOME=<scratch>/xdg`, so the real `~/.config/envoy-peer` was never touched.
Pane baseline: `herdr pane list` saved before the first run; compared after every step.

## Environment limits found during the run

- codex: installed and logged in (`probe.sh auth codex` → `ready`), but its configured provider `aibox/glm-5.2` was unreachable. The pane showed "Reconnecting... waiting for network / Connection failed: error sending request", so codex never produced a result.
- codex updated itself from 0.153.4 to 0.165.0 on its first launch in the pane, behind a "Press enter to continue" screen.
- grok, omp, agy: installed but not logged in. They were not launched in this phase, because their sign-in screens open browser pages.
- So no envoy kind on this machine could finish a task. The parts of the loop that need a working envoy were proven in phase 2 through the claude role (see AC5).

## Acceptance criteria

| AC | What was run | Result | Panes |
|----|--------------|--------|-------|
| 1. Options are only installed kinds other than the controller | `probe.sh controller` → `claude`; `probe.sh list --json` | `codex agy omp grok`; `claude` is absent; every entry is `selectable` | none |
| 2. `--kind codex` dispatches with no kind question | `new-run.sh fix-greet --kind codex --cwd <repo>` | Run `261028-1542-fix-greet-1bd57f` was created without asking anything. Defaults: reviewer `claude`, `max_rounds 3`, `timeout_minutes 60`, placement `split` | none |
| 3. An unverified kind is guided once, state is global, a second project does not ask again | Fresh XDG: `state.sh get codex` → exit 1; Step 3 path: `probe.sh auth codex` → `ready`, then `state.sh set-verified codex --version "codex-cli 0.153.4" --probe auth`; then from `/`: `probe.sh auth codex` → `ready` and `state.sh get codex` prints the timestamp | Pass for codex (probe path). The smoke onboarding path for `no-probe` kinds was not rerun (grok is not logged in). Phase 2 showed grok's sign-in screen reports `idle`, which surfaces as exit 6 with `--no-read`, and SKILL.md Step 3 handles exit 6/7 as possible sign-in screens | none |
| 4. Run folder with brief, result, reviews, run.json; a brief without acceptance criteria is refused | Brief built from `references/brief-template.md`; `check-brief.sh brief.md --run $R` → exit 0. `start.sh` recorded baseline head `5e22f21`, stash `70295b5`, dirty true; `baseline-status.txt` lists ` M README.md` and `?? notes.txt`. Run folder: `brief.md baseline-status.txt baseline-untracked.sha run.json`, mode 700/600. Refusal: the same brief with an empty Acceptance criteria section → `empty: Acceptance criteria`, exit 1; with the section removed → `missing: Acceptance criteria`, exit 1 | Pass. `result.md` and `review-<n>.md` were not produced, because codex could not reach its provider | envoy `wC:p8J` opened by `start.sh` |
| 5. Loop to ACCEPT or max rounds; the final message has only status, summary, rounds and paths | Dispatch: `prompt-wait.sh --role envoy --text … --round 1` | Not proven end to end. Dispatch reached `dispatched_at 10:13:28Z`, round 1. The call then returned exit 3 after 300 s with the tree unchanged, because the provider was down. Phase 2 had proven the reviewer half live with the claude role: `Verdict: ACCEPT`, exit 0, guard `clean`, conflicts `present`. The FINDINGS → ACCEPT loop and the final message are covered only by `evals/evals.json` case 4 | `wC:p8J` |
| 6. Both panes close at the end, including on errors; `--cleanup` clears abandoned runs | `rs set status blocked`, then from the sandbox: `cleanup.sh --all` (dry run), then `cleanup.sh --all --yes` | The dry run listed the run and left the pane open. `--yes` closed `wC:p8J`; the ledger shows `status cleaned`, `final_status blocked`, `envoy.closed_at 10:21:04Z`, and `processes_at_stop` codex 70809 and node 70807. Both PIDs were gone afterwards. The pane list matched the baseline | `wC:p8J` closed |
| 7. From a codex host, options exclude `codex` and include `claude` | A codex agent `portable-codex` was started in a new pane `wC:p8K` with `herdr agent start … --kind codex`. The scripts then ran with `HERDR_PANE_ID=wC:p8K`: `probe.sh controller` → `codex`; `probe.sh list --json > portable.json` → `claude agy omp grok`; `prompt-wait.sh --help` → exit 0, 19 lines | Partial. Kind detection from a live codex pane is proven. Codex itself running the commands is not, because its provider was down. The commands were run by the controller using the codex pane's id | `wC:p8K` opened and closed |
| 8. `install.sh` links, reruns cleanly, `--uninstall` removes | Phase 1 block: install twice, `readlink`, uninstall, run through the link, `--dry-run`, `--force` refusing a real folder, project link and unlink, refusal in a repo that does not ignore the link. Sandbox: `--project` refused until `.claude/` and `.envoy/` were ignored, then linked, ran `probe.sh args codex` through the link, and unlinked. Real `~/.claude/skills`: absent before; linked; `SKILL.md` showed `name: envoy-peer`; `probe.sh` ran through the link; `--uninstall` removed it | Pass | none |

## Onboarding and resume, observed live

These are new evidence. Phase 2 could not trigger exit 4.

1. First prompt to codex → exit 4 `blocked`: the codex update screen. Only the pane label was given to the user; the pane was not read during onboarding. The user pressed Enter in the pane.
2. Codex updated and quit; the pane stayed open. The next call → exit 10 (`agent_not_found`), with `prompted_at` still null. `start.sh` was run again; it reused `wC:p8J` and restarted codex in it.
3. Next prompt → exit 4 `blocked`: the codex trust screen for the sandbox. The user chose Trust.
4. Next prompt was sent: `prompted_at` and `dispatched_at` were set, round 1.

## Bugs found and fixed during the run

- **`prompt-wait.sh` (exit 4 before sending).** The message said "call again without --text", which would wait forever on a prompt that was never sent. It now says "nothing was sent; call again with the same --text". Re-run live: exit 4, `prompted_at` still null, new wording shown. SKILL.md exit rows 3 and 4 and `references/run-contract.md` (exit 4) now say when to resend `--text`.
- **SKILL.md exit 10.** A CLI that quits after a self-update screen left the run stuck. Exit 10 with no `prompted_at` now means: run `start.sh` once more, which reuses the pane. Otherwise: Step 8, BLOCKED. Proven by step 2 above.
- **SKILL.md slug hint.** `new-run.sh greet fix` failed with "only one slug is allowed". The hint now says to join 2–4 words with hyphens (`fix-greet`).

## Cleanup check

- Pane list after every step, and at the end: identical to the baseline. Opened and closed: `wC:p8J` (envoy) and `wC:p8K` (portable check). No reviewer pane was opened.
- Run folders: the sandbox run was cleaned by `cleanup.sh`, then its `.envoy/` was removed. `head-chief/.envoy` never existed.
- Processes: codex 70809 and node 70807, both from the envoy pane, ended when the pane closed.
- Two processes were left behind and **not killed**: codex 0.165.0 `app-server` daemons, PIDs 70857 and 70885. They have PPID 1, started at 15:54:07 local, and run from `~/.codex/packages/app-server-daemon/releases/0.165.0-…/bin/codex`. Codex started them itself after its self-update, as a shared per-user service, so this run does not clearly own them. The user can stop them with `kill 70857 70885` if they are not wanted.
- The `skills` CLI check (`npx skills … --skill envoy-peer`) was not run: the package is not in the npx cache and was not installed for this test. Discovery depends on `skills/envoy-peer/SKILL.md` frontmatter (`name`, `description`), which is present. Check after push.

## Code review

Ran `code-review` at level high on `skills/envoy-peer` and `install.sh`. It returned 10 findings. Each one was checked against the source and fixed:

| Finding | Fix | Evidence |
|---------|-----|----------|
| The reviewer guard ignored HEAD, so a reviewer commit looked `clean` | `guard_snapshot` records `head`, `index_sha` (from `git ls-files -s`) and the hash of the per-path manifest. `guard end` names HEAD and index changes | Scratch repo: no change → `clean`; reviewer commit → `changed HEAD moved … index changed`; restage → `changed index changed … b.txt`; new file → `changed c.txt` |
| The guard hashed the tree twice per call | The manifest is written once (`guard-<n>.manifest`, `guard-<n>.after.manifest`) and hashed from the file | Same run. `run-contract.md` documents the new fields and file |
| SKILL.md checked `review-{n}.md` absent before every reviewer prompt, which blocked the exit 7 and `conflicts` missing re-prompts | The check runs once per round. Re-prompts skip it. `conflicts` missing re-begins the guard first | SKILL.md Step 7, items 1 and 4 |
| Status stayed `fixing` during re-review, so recovery after compaction could re-prompt the envoy | `rs set status reviewing` before each round's reviewer prompt. The Ledger section says how to tell each role's turn apart (`prompted_at` with null `settled_at`, `Round:` line, an existing review file) | SKILL.md Ledger and Step 7, item 1 |
| `start.sh` on a reused pane could type the launch command into a CLI still in the foreground | `at_shell_prompt` (Herdr `process-info`: foreground group == shell pid) is required before `agent start` on a reused pane; otherwise exit 4 `pane busy` | Live: pane `wC:p8P` running `sleep 300`, recorded as the envoy → exit 4, `sleep` untouched |
| `terminal_id` was read from `pane list` after the split and could be stored as null | Read from the split output (`.result.pane.terminal_id`, confirmed live), then `pane list`; with neither, the new pane is closed and start fails | Live: run envoy pane `wC:p8N`, ledger id equals the pane list. A second `start.sh` resumed the same pane |
| `cleanup.sh` stopped at a refused envoy pane and left the reviewer pane open | Both roles are always attempted; the run is marked cleaned only when neither failed | Live: envoy id altered → exit 9, reviewer `wC:p8Q` closed, envoy `wC:p8N` left open, status unchanged; id restored → cleaned |
| A repo with no commits left the baseline unmarked, so it could be retaken later, and the reviewer got an empty SHA | `take_baseline` notes "repository has no commits yet". SKILL.md Step 7 swaps the diff clause when `SHA` is empty | Unborn repo: `note` set, `dirty: true`, `?? x.txt` recorded |
| The `run_bounded` watchdog left its `sleep` behind and killed only the direct child | `kill_tree` (children first, via `pgrep -P`); the watchdog kills its own sleep when it is stopped | `run_bounded 1 bash -c "sleep 47 & wait"` → rc 143, no `sleep 47` left; `run_bounded 53 true` → no `sleep 53` left; exit codes pass through |
| `install.sh --uninstall` refused a skill that was no longer in the checkout | The `SKILL.md` check moved after the uninstall branch | A dangling link was removed with exit 0; installing a missing skill still fails with exit 1 |

After the fixes: `bash -n` and `shellcheck -x` are clean on every script, the phase 3 SKILL.md greps still match, and SKILL.md is 136 lines. Panes opened for these checks (`wC:p8M`, `wC:p8N`, `wC:p8P`, `wC:p8Q`) were all closed. The pane list matched the baseline, and no new codex process remained.

The secret grep (`sk-[A-Za-z0-9]|xai-|eyJ|auth\.json`) has three hits, all false positives: "Task-specific" in `references/brief-template.md`, and the two redaction patterns in `scripts/lib.sh` that mask such tokens.

## Live rerun with grok and agy

Later the same evening the user logged grok and agy in on free-tier accounts. Both answered a one-word `-p` prompt in about 8 s. Two blockers remained:
- omp has no models configured (`omp models`: "No models available. Set API keys").
- codex still sends requests through a local 9Router proxy (`127.0.0.1:20128`), and nothing was listening there.

The controller followed SKILL.md step by step in the same sandbox, with the same scratch XDG folder.

| What | Run | Result |
|------|-----|--------|
| AC3 smoke onboarding for a `no-probe` kind | `fix-greet` (grok), `staged-findings` (agy) | Both returned exit 6 (stalled) on the first smoke prompt, and no file was written. The user checked each pane: grok showed nothing pending; agy had a setup screen, which the user cleared. The same smoke was resent and returned exit 0 with `READY`. Then `state.sh set-verified grok\|agy --probe smoke` ran, and `state.sh get grok` printed the timestamp |
| AC4 and AC5, loop to ACCEPT in round 1 | `261028-2055-fix-greet-36f1e5`: envoy grok `wC:p8R`, reviewer claude `wC:p8S` | The envoy returned `Status: DONE`. The reviewer's first prompt hit Claude Code's folder-trust screen, so it returned exit 4 with "nothing was sent". The user trusted the folder, and the same `--text` was resent: `Verdict: ACCEPT`. Guard `clean`, git-meta `same`. The review's Baseline check attributed ` M README.md`, `?? notes.txt` and `?? .gitignore` to the baseline and matched the untracked hashes. `./test.sh` → PASS. Only `greet.sh` changed |
| AC5, FINDINGS → fix → ACCEPT (staged) | `261028-2102-staged-findings-e99a13`: envoy agy `wC:p8V`, reviewer claude `wC:p8W` | The brief said openly, under Hidden points, that round 1 should fix only the misspelling. The round-1 review gave `Verdict: FINDINGS` with guard clean. `conflicts` → `present`, so the user was asked and `decision-1.md` was written. Status went `fixing`, round 2. The envoy prompt named both `review-1.md` and `decision-1.md`; the result had `Round: 2` on line 2 and `Status: DONE`. The re-review gave `Verdict: ACCEPT` with guard clean. Status was `accepted`, then `cleaned`. The run folder holds `brief.md result.md review-1.md review-2.md decision-1.md guard-{1,2}{,.after}.manifest run.json` |
| AC5, final message | both runs | The fields Step 9 needs are available: `rs extract Summary result.md --max-lines 4` gives a one-paragraph `> ` quote, plus the round count and the paths |
| AC6 | both runs, plus a grok probe run | `cleanup.sh --run` closed 2, 2 and 1 panes. The pane list equals the list saved before the rerun, and no grok, agy or claude process was left |
| AC7, a non-claude agent runs the scripts itself | `261028-2101-grok-runs-probe-738fd6`: grok `wC:p8T` | grok ran `probe.sh controller` and `probe.sh list` in its own pane and wrote `controller: grok`, then `claude`, `codex`, `agy`, `omp`, all `selectable`. Together with the phase-4 run from a codex pane (`controller` → `codex`, list without `codex`), this covers AC7. codex itself could not run the commands (no 9Router) |

Bugs found by the rerun and fixed:

- `run-state.sh` `section()` read the closing contract line (`Verdict: …` in a review, `Status: …` in a result) as part of the last section. So `conflicts` printed `present` for every review whose Conflicts section said "None.", and `extract Unresolved` quoted the Status line. A section now also ends at that contract line. Recheck: the real `review-1.md` gives `none`, and `extract Unresolved` gives `> - None.` only. Fixtures: a conflict bullet → `present`, a bare "none" → `none`, no Conflicts heading → `missing` (exit 7).
- The claude reviewer wrote "None." followed by an explanation in both runs, which the strict check reads as a conflict. The check stays strict, because extra text may hold a real conflict. `references/review-template.md` now says to write only "None." and that any other text stops the run for the user. That wording has not been rerun live. In the second run, the controller treated the round-2 `present` as covered by the user's round-1 decision, since the text only quoted that decision.

Observations, no change made:
- On a CLI's first launch in a folder, `start.sh` can report ready before the CLI draws its trust or setup screen. `prompt-wait.sh` then either catches it as `blocked` before typing (claude) or reports `stalled` (grok, agy). In both cases the documented recovery (exit 4 or 6 → user → resend) completed the run.
- The redaction filter masks 40-hex commit hashes in quoted lines (`git diff --stat [redacted]`). This is harmless, since the run ledger keeps the real SHA.

## Not proven, and why

- codex as a working envoy, or codex itself running the scripts: codex reaches its model only through the local 9Router proxy, which was not running. AC2 (dispatch with no question) and codex onboarding were still proven with codex.
- omp: no models configured.
- The new review-template wording: not yet seen in a live review.
- Exit 11 (`not ready` after start): not triggered by any installed kind.

Status: DONE
Summary: AC1, AC2, AC3 (probe path), AC4, AC6 and AC8 pass live, AC7 passes at script level, three skill bugs found by the run and ten code-review findings are fixed and rechecked. The end-to-end review loop (AC5) is still unproven because no installed envoy kind can reach a model right now.
Concerns/Blockers: rerun step 4.3 of phase 4 once codex's provider is reachable, or once grok, omp or agy is logged in.
