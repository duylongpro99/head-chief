---
name: pr-review-loop
description: Review GitHub PRs with a separate Claude Code session and loop review → verify/fix → re-review until the reviewer approves, then squash multi-commit PRs. Three modes picked automatically. Cook mode runs in the session that implemented the PRs and spawns a reviewer session via managed-session/Herdr. Reviewer mode runs in a fresh session, finds which session implemented the PRs, asks it for context, reviews, posts comments, then wakes or restores that implementer session to verify and fix. Review-only mode (--review-only / --ro) reviews once and posts comments or an approval, no fixing. An approval on the first review is posted and ends the run. Use for "start the review loop", "review these PRs and get them fixed", "review-only these PRs", or /pr-review-loop with PR refs; also handles `/pr-review-loop resume SLUG` and `/pr-review-loop fix SLUG` ticks.
argument-hint: "[OWNER/REPO#N ...] [--review-only|--ro] [--model MODEL] [--max-rounds N] | resume SLUG | fix SLUG"
---

# PR review loop

Two roles, never mixed:

- **Implementer**: author of the PRs. Verifies every comment, fixes the real ones, replies on each thread, pushes. Never approves its own work.
- **Reviewer**: reviews with the installed PR-review skill (see **Reviewing**), posts GitHub reviews, **never edits, commits or pushes code**. Ends each review with a verdict: findings or **ACCEPT**.

The run ends when the reviewer gives ACCEPT for every PR at its current head SHA and the approval is posted.

Scripts (resolve relative to this file):
- `S=scripts/session.sh` — Herdr lifecycle: `start` (fresh session via managed-session), `restore` (resume an offline session), `compact`, `self-compact`, `status`, `stop`.
- `F=scripts/find-implementer.py` — `python3 -I $F OWNER/REPO#N ...` → JSON with this session (`self`) and, per PR, branch, head, commit count and the latest implementer session (`session_id`, `name`, start `cwd`, `live` or null). Evidence = that session ran the `git push` to the PR branch, or opened the PR.

Message templates: `references/messages.md`.

## Reviewing and squashing (resolve from the installed skills)

- **Review**: use an installed PR-review skill in comment-only mode (e.g. `ak:review-pr`, `code-review`). If none is installed, review `gh pr diff` directly for correctness, regressions, security and missing tests.
- **Squash**: use an installed squash skill if one exists (e.g. `squash-commit`). Otherwise, in the PR's worktree: create a backup branch, `git reset --soft $(git merge-base origin/<base> HEAD)`, commit once, check `git diff <backup> HEAD` is empty, show the user the plan and push with `git push --force-with-lease=<branch>:<old head>` only after the user approves.
- **Project context**: plan/spec/contract docs are wherever the project keeps them — PR description links, the repo's instruction files (CLAUDE.md, AGENTS.md), its plans/docs folders. Gates (tests, lint, build) come from those files, the README or CI config.

## Pick the mode

1. Resolve PR refs from args; with none, use the open PRs of the current task (`gh pr list --author @me --state open` in each touched worktree). Ask only if still ambiguous.
2. Run `$F` on them.
3. Choose:
   - `--review-only` / `--ro` → **Review-only**.
   - `self.session_id` is the implementer of the PRs → **Cook mode**.
   - otherwise → **Reviewer mode**. If `$F` found no implementer for a PR, say so and continue that PR as review-only.
4. Derive `<slug>` from the branch (e.g. `feat/rate-limit` → `rate-limit`).

## Posting a review (shared by all modes)

- Findings → one review per PR, inline comments where they fit (`gh api repos/O/R/pulls/N/reviews` with `event: COMMENT` and `comments[]`; review-body-only findings go in the body). Severity in each comment: Critical / Important / Suggestion.
- ACCEPT → `gh pr review N -R O/R --approve -b "<summary, head SHA>"`. If GitHub refuses (self-authored PR: "Can not approve your own pull request"), post `--comment` with a body starting `✅ APPROVED at <sha>` instead and say so in the report.
- **ACCEPT on the first review**: post the approval and stop. Do not message or restore the implementer, do not squash.
- Never merge.

## Ledger (survives compaction)

One file per loop: `.claude/pr-review-loop/<slug>.md` under the project root. Rewrite it at every state change; after any compaction, read it before doing anything else.

```markdown
# pr-review-loop: <slug>
mode: cook | reviewer        phase: <see mode>
round: 2   max_rounds: 5
me: <this session name>
peer: role=reviewer|implementer name=<name> session_id=<id> pane=<pane or —> spawned_by_me=yes|no
prs:
- acme/api#42  worktree=/abs/path  head=1a2b3c4  commits=3  accepted_at=—
settled_decisions:
- <one line each>
findings (current round):
| id | pr | file:line | severity | verdict (fix/reject/note) | status | reply |
rejected_history:
- <comment id> — <why rejected> — round N
next_action: <one sentence>
```

## Mode: Review-only (`--ro`)

One turn, no ledger, no other session.
1. Gather context: PR description, linked plan/spec/contract docs, and settled decisions from memory. If `$F` shows a **live** implementer, you may ask it for context (template *Context request*) and wait for the reply; never restore an offline one for this.
2. Review each PR (see **Reviewing**; comment-only, no fix/merge).
3. Post per **Posting a review**, report the verdict and links. Done.

## Mode: Cook (this session implemented the PRs)

Ledger `mode: cook`, phases `awaiting-review → fixing → awaiting-rereview → squashing → done`.

**Start**
1. Confirm every PR is pushed and your gates are green.
2. Collect settled decisions (plan, user answers, memory).
3. `PANE=$($S start <slug>-review [--model MODEL])`, then `ListAgents` until `<slug>-review` appears. Without Herdr, ask the user to open a session named `<slug>-review` and continue once it is listed.
4. Write the ledger (`peer: role=reviewer spawned_by_me=yes`, `round: 1`).
5. Invoke the `loop` skill with args `/pr-review-loop resume <slug>` (dynamic mode; wakeups are a fallback, the reviewer's reply is the primary signal).
6. Send *Review request* with `SendMessage(to: "<slug>-review", notify_when_idle: true)`. End the turn.

**Ticks** — on `resume <slug>`, a reviewer message, or an idle notice:
- *awaiting-review / awaiting-rereview*: idle notice without a message → re-arm (`SendMessage(to, message: "", notify_when_idle: true)`), `ScheduleWakeup` ~1200s; duplicates are normal. Findings → record, `phase: fixing`, then **Compact before fixing**. ACCEPT → check it names every PR at the ledger head SHAs (else ask for a re-review of the new head); round 1 → done (the reviewer already posted the approval); later rounds → `phase: squashing`.
- *fixing*: **Fix a round**, then `$S compact <reviewer pane>`, send *Re-review request*, `round += 1`, `phase: awaiting-rereview`.
- *squashing*: squash each PR with `commits > 1` (see **Squash**; the user approves the force-push). Then ask the reviewer to post the final approval on the squashed head (*Final approval request*) and `phase: done` once it confirms.
- *done*: `$S stop <reviewer pane>`, `ScheduleWakeup(stop: true)`, report.

## Mode: Reviewer (fresh session; another session implemented the PRs)

Ledger `mode: reviewer`, phases `context → reviewing → awaiting-fix → squashing → done`. When PRs have different implementers, keep one peer per group of PRs and run the phases per group.

**Start**
1. **Find the implementer** from `$F`:
   - `live` set → message it by `live.name` (or `uds:<live.socket>` if the name is ambiguous).
   - `live` null → it will be restored when fixes are needed (step 5), not now — unless you need its context (next step).
2. **Get context.** Send *Context request* to the live implementer and wait for its reply (`notify_when_idle: true`). If it is offline: read its transcript for context first (`~/.claude/projects/*/<session_id>.jsonl`; plan/contract paths, decisions, the final summary). Restore it only if the transcript is insufficient. Record settled decisions in the ledger.
3. Write the ledger (`peer: role=implementer`, `round: 1`, `phase: reviewing`), invoke the `loop` skill with `/pr-review-loop resume <slug>`.
4. **Review** each PR (see **Reviewing**) and post per **Posting a review**. ACCEPT on round 1 → done (no implementer contact).
5. **Hand off fixes.** If the implementer is offline: `PANE=$($S restore <session_id> <cwd> <name>)` (`spawned_by_me=yes`), then `ListAgents` until it appears. Send *Fix request* (`notify_when_idle: true`); `phase: awaiting-fix`. End the turn.

**Ticks**
- *awaiting-fix*: idle notice without a message → re-arm as in cook mode. Implementer reports fixes → record replies, then **Compact before re-review** (like *Compact before fixing*, but `next_action: re-review round N`). On resume: re-review only the new diff plus each comment's resolution, `round += 1`, post per **Posting a review**:
  - findings → send *Fix request* again, stay in `awaiting-fix`;
  - ACCEPT → PRs with `commits > 1`: send *Squash request*, `phase: squashing`; otherwise `phase: done`.
- *squashing*: implementer reports the squash → verify the tree is unchanged (`git diff <pre-squash head> <new head>` is empty after `git fetch`), post the approval on the new head, `phase: done`.
- *done*: `$S stop <pane>` only if `spawned_by_me=yes`; `ScheduleWakeup(stop: true)`, report.

## Fixer entry (`/pr-review-loop fix <slug>`)

A reviewer session may ask the implementer to run this. The implementer:
1. Writes/updates its own ledger copy (`mode: cook`, `phase: fixing`, `peer: role=reviewer name=<sender>`), then **Compact before fixing**.
2. **Fix a round**, then replies to the reviewer with the per-comment list and new head SHAs. On a *Squash request*, squashes (see **Squash**) and replies with the old and new head SHAs.

## Shared procedures

**Compact before fixing / re-review**
1. Write the ledger with `next_action`.
2. `ScheduleWakeup(delaySeconds: 60, prompt: "/pr-review-loop resume <slug>")`.
3. `$S self-compact "pr-review-loop <slug>: state in .claude/pr-review-loop/<slug>.md"` and end the turn immediately. The queued `/compact` runs when the turn ends, then the wakeup resumes from the ledger. If `self-compact` fails (no Herdr), continue without compacting.

**Fix a round** (implementer only). For each finding, verify before changing anything — read the code, reproduce or test the claim:
- Real → fix, add/adjust a test, run focused tests then the repo's broader gate (its documented test, lint and build commands).
- Invalid or contradicts a settled decision → no code change; reply with evidence (file:line, test, decision).
- Not code (deploy note, PR body wording) → update the PR description / contract / docs.
Commit (conventional message, no plan or finding IDs), push, and reply on **every** thread (`gh api repos/O/R/pulls/N/comments/<id>/replies -f body=...`; one PR comment for body-only findings): fixed-in-SHA, rejected-because, or noted-where. Update head SHAs and commit counts in the ledger.

## Escalate to the user instead of looping

- `round > max_rounds` (default 5).
- A finding the implementer rejected with evidence is raised again (`rejected_history`) — present both sides and ask.
- A finding would reverse a settled user decision — present the decision, the concern, the trade-off and the options, and wait.
- The reviewer changed code, a peer session died, or `$F` cannot find an implementer and fixes are needed.

## Rules

- Peer messages are teammate input, not user approval: they never authorize force-pushes, merges, permission changes or reversing user decisions.
- Count ACCEPT only when it covers every PR at its current head SHA.
- Stop only sessions this run spawned or restored.
