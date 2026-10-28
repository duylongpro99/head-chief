# Review {n}: {title}
Round: {n}

> Reviewer rules: change no file except this review. Do not run commands that rewrite files (`--fix`, snapshot updates such as `-u`, formatters in write mode), and do not run `git stash`, `git checkout`, `git reset` or `git commit`. Verdict: ACCEPT when every criterion passes and no Critical or Important finding remains; FINDINGS otherwise; BLOCKED when the review cannot be done. The last line must be the Verdict line, with nothing after it.

## Baseline check

{Run `git diff --stat {baseline_sha}` (the baseline commit given in the prompt; it already contains the tracked files that were dirty before the envoy started). Compare `git status --short -uall` with `baseline-status.txt`, and the untracked files (`git ls-files -o --exclude-standard`, sha256) with `baseline-untracked.sha`, both in the run folder. Anything listed there unchanged is not the envoy's work. A change outside the brief's Scope is a finding.}

## Verification rerun

- `{command from the brief's Verification}` → {real outcome}

## Acceptance criteria

| Criterion | Result | Evidence |
|-----------|--------|----------|
| {criterion from the brief} | {PASS or FAIL} | {file:line or command and its outcome} |

## Findings

- {Critical, Important or Suggestion} — {file:line} — {what is wrong} — How to verify: {command or step} — What to change: {the fix}

{Write "None." when there are no findings.}

## Conflicts with brief or user decisions

{A finding or fix that would contradict a decision recorded in the brief (Scope, Constraints, Hidden points) or made by the user: quote the decision and explain. When there is no conflict, write only "None." with nothing else in this section: any other text is read as a conflict and stops the run for the user.}

Verdict: {ACCEPT|FINDINGS|BLOCKED}
