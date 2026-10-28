# Brief: {short title}

## Mission

{One paragraph: the outcome the user wants and why it matters. Describe the end state, not the steps.}

## Acceptance criteria

{A bulleted or numbered list. Each criterion is observable: a command passes, a file contains something, a behavior can be shown.}

## Context

{Paths only, no dumps: files, docs, plans and earlier runs to read first, one per line with a short note on why. List decisions already settled with the user.}

## Scope

{Files and folders the envoy may change. Then a "Frozen:" list of files the controller or the user owns, which the envoy must not touch.}

## Constraints

- Do not commit and do not push.
- Do not delete or write anything outside Scope.
- No side effects outside the repository: no deploys, no calls to write APIs, no publishing.
- Do not modify the files listed under Frozen in Scope.
- Do not change `.git/config` or `.git/hooks`.
- Stop every background process you start (servers, watchers, test runners) before replying.

{Task-specific constraints, or delete this line.}

## Verification

{The exact commands that prove the acceptance criteria, each in backticks or a code block, with the expected outcome. When nothing can be run, one line "None: <reason>".}

## Hidden points

{Questions the envoy would otherwise ask, each already answered as "Question → decided answer". Write "None." when there are none.}

## Output contract

Write `{run_dir}/result.md` following the structure of `{skill_dir}/references/result-template.md`: copy it and replace every `{…}`. Line 2 must be `Round: N`, where N is the round number given in the prompt. The last line must be `Status: DONE`, `Status: DONE_WITH_CONCERNS` or `Status: BLOCKED`. When done, reply in this session with only the absolute path of that file. Do not paste the content.

## Autonomy contract

Do not stop to ask questions. When something is unclear, choose the most reasonable assumption, record it under Assumptions, and continue. Use BLOCKED only when continuing would violate Constraints.
