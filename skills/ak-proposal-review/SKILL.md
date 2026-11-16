---
name: ak-proposal-review
description: "Turn a proposal into one local HTML draft with per-section feedback boxes, then revise that same file round by round from the feedback the user pastes back, until every section is agreed. Not for hosted or shared pages, showcases, or implementation plans."
when_to_use: "Invoke when the user wants to read a proposal, solution or design as a local HTML file and give feedback on the page itself, or pastes back feedback exported from such a draft."
category: workflow
keywords: [proposal, feedback, review, html, draft, local, discussion, góp ý, bản thảo, đề xuất]
argument-hint: "[proposal topic or draft path] [pasted feedback or path to the exported .md]"
license: Proprietary
metadata:
  author: atoria
  version: "1.0.0"
---

# Proposal Review (`ak-proposal-review`)

Agree a proposal with the user through a local HTML draft. The user reads the page, marks
each section, answers the open questions, copies the feedback as markdown and pastes it
into the session. You revise the same file and raise the round number. The loop ends when
every section is agreed and no question is open. The user never has to retype an opinion
per section in chat, and you never have to guess how far they agree.

## When to use, and what to hand off

Use it for a proposal with several sections and several decisions, where more than one
round of discussion is likely.

- A single decision, or a question answerable in chat: answer in chat.
- A page to host, publish or share by link: `/ak-preview` or `/ak-show-off`. This skill's
  product is a file on the user's disk, and the user who asked for it said "không sử dụng
  artifact". Do not call an artifact or publishing tool from this skill, and do not start a
  server for the page.
- The proposal's content does not exist yet: research or brainstorm first
  (`/ak-research`, `/ak-brainstorm`), then come back with the content. This skill
  presents and negotiates a proposal; it does not produce one.
- The proposal is agreed and the user wants a plan or code: stop here. State the next step
  and wait to be asked; `/ak-plan` owns planning.

## Files

- **Draft:** one HTML file in the repository's reports directory, named
  `proposal-<YYMMDD>-<HHMM>-<slug>.html`. Every round is written to this same path, so the
  user only reloads. CSS and script are inline and nothing is fetched from the network.
- **Template:** copy `assets/proposal-template.html` and fill it. Its stylesheet and its
  `review-core` script are shared by every draft; leave the script unchanged. Read
  `references/page-contract.md` before filling the template or adding a kind of block.
- **Saved versions:** `scripts/proposal_draft.py` keeps earlier versions beside the draft in
  `<draft-name>.versions/`.

## Round 1: build the draft

1. Gather the proposal from the session or the file the user pointed to. If a claim the
   page will make is not established yet, list it under "Còn chưa kiểm chứng" on the page
   instead of presenting it as settled.
2. Copy the template to the draft path and fill it in the user's language. The page must
   be enough on its own: carry the context, the glossary and the reasoning into it. A
   sentence such as "the report says" or "see the research file" sends the reader away to
   find something, which is the complaint that forced a rewrite of the first draft.
3. Give every section a feedback box, every decision you need a question block with one
   recommended option and the reason, and every mechanism a figure that shows the real
   steps and numbers. Keep secrets out: name the variable or file that holds a credential,
   never its value.
4. Run the checks under "Before reporting", then report with the template in
   `references/feedback-rules.md`.

## Each later round: revise from feedback

Feedback arrives as pasted markdown titled `# Góp ý vòng N cho đề xuất <name>`, as a path
to the downloaded `.md`, or as plain chat. Read `references/feedback-rules.md` before
acting on it; its rules come from specific mistakes in the session this skill was drawn from.

1. Read all of it. A note is feedback wherever it was typed, including a note inside an
   "agreed" section and a note with no verdict.
2. Check or look up what the user asked you to check, and write the result into the page.
3. Start the round:
   - feedback exported from the page: `python3 scripts/proposal_draft.py new-round <draft>`
     saves `v<N>.html` and raises the round number, so the boxes start empty against the
     changed content;
   - a correction given in chat between rounds: `python3 scripts/proposal_draft.py backup <draft>`
     and keep the round number, so feedback the user already typed stays on the page.
4. Edit the draft itself. A long chat reply in place of the edit is not a revision; the
   user answered one with "bạn update lên file bản thảo". Each replacement must match
   exactly the number of places you intend: use an edit operation that fails on a missing
   or ambiguous match, or a script that asserts the count before replacing.
5. Rewrite the "Thay đổi sau góp ý" section for this round: one line per point the user
   raised, saying what changed and linking to where. Move each answered question out of
   the question section into "Đã chốt". Propagate every new decision to the tables,
   figures and options it affects.
6. Handle every `(chưa chọn)` line. When the option is already described in a section the
   user marked "Đồng ý", take that option, and say on the page and in the report that this
   is your inference and how to overturn it. Ask the user directly about the rest. No
   unanswered question is dropped silently.
7. Run the checks, then report.

## Before reporting

```bash
python3 scripts/proposal_draft.py check <draft> [--forbid "<old wording>"]... [--expect "<text>=<N>"]...
```

The check covers template leftovers, tag nesting, duplicate `id` and `data-id`, broken
internal links, remote resources, the round number against its visible labels, question
blocks, ids the page logic reads, and script syntax through `node --check`. Pass
`--forbid` for each role name, field id or phrase this round replaced, so no wording from
the earlier version survives. Fix every `FAIL`. A `NOT RUN` line is not a pass: carry it
into the report.

Then look at the page. When a browser automation capability is available and can open a
local file, open the draft, press one verdict button, answer one question, press
"Sao chép góp ý" and compare the export with the format in `references/page-contract.md`.
When no such capability is available, or the sandbox blocks opening the file, say that
the page has not been seen in a browser and give the user the exact command:
`open <absolute path>` on macOS, `xdg-open` on Linux, `start` on Windows. The page behind
this skill went through four versions without the agent once seeing it rendered, and
every report said so. Never describe the look or behavior of a page you did not see.

## Done

The draft is "đã chốt" when the latest feedback marks every section "Đồng ý", every
question is answered or resolved by a stated inference, and
`proposal_draft.py check <draft> --final` passes. Mark the page as final in its header,
tell the user what the next step would be, and do not begin it.

For any single revision, done means: the draft is updated in place, the check passes or
its failures are reported as failures, and the report follows the template, including
what was not verified.

## Resources

- `assets/proposal-template.html`: the page skeleton, stylesheet, illustration blocks and
  the shared feedback script. Copy it for round 1.
- `references/page-contract.md`: markup the script depends on, page structure, export
  format. Read before filling the template or adding a block.
- `references/feedback-rules.md`: how to act on each kind of feedback, and the report
  template. Read before revising and before reporting.
- `scripts/proposal_draft.py`: `check`, `backup`, `new-round`. Python 3 standard library,
  any OS; `node` is optional and only used for the syntax check. Tests:
  `python3 -m unittest discover -s scripts/tests`.
