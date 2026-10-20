# Message templates

Send with `SendMessage(..., notify_when_idle: true)`. Fill every `<...>`.

## Context request (reviewer → implementer)

```text
I'm reviewing <repo#N list> (session <me>). Before I start, please reply with:
- what the PRs are meant to do, and any plan/contract/ticket paths;
- settled decisions I must not flag as defects (user decisions, trade-offs you were told to keep);
- known gaps, follow-ups, or anything intentionally out of scope;
- tests/E2E you ran and their results;
- the worktree path and branch per PR.
Please don't change code now.
```

## Review request (cook → reviewer, round 1)

```text
Please review <repo#N list> and post your findings as GitHub reviews. Do not change, commit or push any code — I (session <me>) verify and fix every comment.

1. Pull the changes (`gh pr checkout <N>` in a checkout of each repo, or `gh pr diff`).
2. Review each PR with your installed PR-review skill in comment-only mode (e.g. ak:review-pr, code-review), or review the diff directly if none is installed.
3. Findings → one COMMENT review per PR, inline where they fit, severity Critical/Important/Suggestion.
   Nothing to flag → approve: `gh pr review <N> --approve`; if GitHub refuses (self-authored), post a COMMENT whose body starts "✅ APPROVED at <sha>".

Settled decisions — do not flag these as defects:
- <one per line>

Context: plan <path>, contract <path>.

Reply with each comment as `id, file:line, severity, one-line summary` (include body-only findings), or exactly "ACCEPT <repo#N>@<sha> ..." for every PR once the approval is posted.
```

## Re-review request (cook → reviewer, round N)

```text
Round <N-1> fixes are pushed. You have been compacted; re-read the PRs fresh.
Re-review <repo#N> (new head <sha>), <repo#M> (unchanged, <sha>).

Per comment: <id>: fixed in <sha> — <what> | rejected — <evidence> | noted — <where>.
Gates run: <tests/lint and result>.

Check that each fix resolves its comment, then look for regressions in the new diff. Same rules: comments only, no code changes, don't flag settled decisions. If you disagree with a rejection, say why with new evidence. Reply with the new comment list, or post the approval and reply "ACCEPT <repo#N>@<sha> ..." for every PR.
```

## Final approval request (cook → reviewer, after squash)

```text
The PRs were squashed with an identical tree: <repo#N> <old sha> → <new sha>. Please confirm `git diff <old> <new>` is empty, post the approval on the new head (approve, or the "✅ APPROVED at <sha>" COMMENT fallback), and reply "ACCEPT <repo#N>@<new sha> ...".
```

## Fix request (reviewer → implementer)

```text
I (session <me>) reviewed <repo#N list> — round <N>. Please run `/pr-review-loop fix <slug>` and handle these comments:

- <id>, <repo#N> <file:line>, <severity>: <one-line summary>

For each: verify before changing anything; fix real ones with tests; reject invalid ones with evidence; reply on every GitHub thread; push. Settled decisions stay as they are: <list or "none">.
Reply to me with per-comment status (`<id>: fixed in <sha> | rejected — <evidence> | noted — <where>`), the gates you ran, and the new head SHA per PR.
```

## Squash request (reviewer → implementer)

```text
<repo#N list> are accepted. Please squash every PR with more than one commit (installed squash skill if any, otherwise backup branch + `git reset --soft <merge-base>` + one commit; the user approves the force-push), then reply with `<repo#N>: <old sha> → <new sha>`. I'll verify the tree is unchanged and post the approval.
```
