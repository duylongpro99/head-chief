# Page contract

What a draft contains and the markup the shared `review-core` script reads. The script
holds no page-specific ids: it finds everything through the attributes below, so adding
or removing a section, a question or a field needs no script change.

## Page identity

```html
<html lang="vi">
<body data-slug="content-studio" data-name="Content Studio" data-round="3">
```

- `lang`: `vi` or `en`. It selects the labels the script renders (verdict buttons, bottom
  bar, export headings). Write the page in the language the user writes in.
- `data-slug`: kebab-case. Storage key is `<slug>-feedback-v<round>`, download name is
  `<slug>-feedback-v<round>.md`.
- `data-name`: short proposal name used in the export title.
- `data-round`: the single source of the round number. The storage key, export title and
  download name are derived from it at load. The visible number is written as
  `<span data-round-label>3</span>`, at least once in the header line. Only
  `proposal_draft.py new-round` changes these numbers, and `check` fails when they differ.

A new round changes the storage key, so every box starts empty. Earlier feedback stays in
the browser under the old key but is no longer shown; tell the user this in the report.

## Structure, in order

1. **Header.** A label line with the round number and date, the title, a short summary of
   the proposal, a note on how to give feedback, and a table of contents linking to every
   section. The note says that the page is a static file and you cannot read the feedback
   until the user pastes it.
2. **Changes and locked decisions** (from round 2; `id="changes"` and `id="locked"`).
   See below.
3. **Content sections.** Context, reasoning, design, each choice with its reason next to
   the alternative considered, rejected directions and risks, roadmap.
4. **Calculator**, only when a number in the proposal depends on the reader's inputs.
5. **"Còn chưa kiểm chứng".** What you have not run, measured or confirmed, with its own
   feedback box. When the user asks you to check something and you do, rename the section
   to reflect that it now holds results.
6. **Question blocks**, then a free field for anything that fits no section.
7. **Sources**, grouped by topic, each with what it supports.

The bottom bar (count of feedback items, "Sao chép góp ý", "Tải file .md", "Xoá hết") is
built by the script; do not write it into the markup.

## Changes and locked decisions

From round 2 the first section answers the previous round:

- One list item per point the user raised, in their words, followed by what you changed
  and a link to the changed section. Six points raised means six items. This section
  describes the latest round only; replace it each round.
- "Đã chốt" (`id="locked"`): every decision the user has made, cumulative across rounds.
  Add the newest ones under their own sub-heading ("Chốt thêm ở vòng N"). A locked
  decision is not reopened; a concern about one goes next to it as a note.
- An inference you made for an unanswered question is marked as an inference right here,
  with how to overturn it.

## Feedback box

```html
<div class="fb" data-id="models" data-title="Model miễn phí và cách xoay vòng"></div>
```

- `data-id` is unique among boxes and stable across rounds. `data-title` is the heading
  the user's feedback appears under in the export, so make it recognisable out of context.
- The script fills the box with three verdict buttons (one may be pressed; pressing it
  again clears it) and a free note.
- One box per section. A section holding several separate choices gets one box per
  choice, titled "Lựa chọn: ...", so the user can agree with one and contest another.

## Question block

```html
<div class="q" data-label="Nạp tiền OpenRouter">
  <h3>Có nạp 10 USD vào OpenRouter một lần không?</h3>
  <p class="note">Vì sao cần quyết, và vì sao tôi khuyên phương án đầu.</p>
  <div class="opts">
    <label class="rec"><input type="radio" name="credit" value="Có nạp"> Có. Giới hạn lên 1.000 lượt mỗi ngày (tôi khuyên)</label>
    <label><input type="radio" name="credit" value="Không nạp"> Không. Chấp nhận mỗi bài mất vài ngày</label>
  </div>
  <input type="text" id="credit-other" data-field="Nạp tiền OpenRouter" placeholder="Hoặc ghi câu trả lời của bạn">
</div>
```

- One block per decision you need. `data-label` is the short label in the export; the
  radio `value` is the short answer text in the export.
- One radio `name` per block, unique on the page. Exactly one option has `class="rec"`
  and says "(tôi khuyên)" in its text; the note gives the reason. The user is free to
  pick another option or write their own, and has done both.
- The free-text field is optional. A block may also have only a free-text field.
- Once answered, the block leaves the page and the answer moves to "Đã chốt".

## Fields and calculators

- Any `input`, `textarea` or `select` with an `id` and `data-field="<label>"` is saved and
  exported. Inside a question block it joins that question's answer. Inside a
  `data-export-group` it is exported under the group title. Elsewhere it is exported as
  its own `## <label>` section when not empty.
- A calculator is an element with `data-export-group="<title>"`. Its fields are exported
  as `- <label>: <value>`, and any element with `data-out="<label>"` exports its text, so
  the user's chosen inputs and the computed result travel with the feedback.
- Calculator logic goes in `<script id="page-logic">`, placed before `review-core`. It
  recomputes on the `review:change` document event, which fires after saved values are
  restored and after every input.
- State on the page whether starting values are your assumption or a measurement. Once
  the user has chosen values, make those the defaults in the next round.

## Illustrations

The template ships these blocks, all plain HTML and CSS inside `.figure` with a `.cap`
caption: numbered flow coloured by who performs each step (`.flow` with `.c-1`/`.c-2`/
`.c-3` and a `.legend`), cards, glossary (`dl.terms`), table (`.tw`), before/after pair
(`.pair`), file tree or command listing (`pre.tree`), roadmap (`.road`). A figure earns
its place by showing the proposal's actual mechanism, names and numbers. Add a new block
type with inline CSS in the same style when none fits; do not load a drawing library.

## Export format

```markdown
# Góp ý vòng <N> cho đề xuất <data-name>

Ngày: <local date and time>

## <data-title of a box>
- Đánh giá: <Đồng ý | Cần bàn thêm | Không đồng ý>
- Ghi chú: <note>

## <data-export-group title>
- <field label>: <value>
- <data-out label>: <text>

## Câu trả lời
- <question data-label>: <answer | (chưa chọn)>

## <label of a free field, for example Điều còn thiếu>
<text>
```

A box the user did not touch is absent. Every open question is listed, unanswered ones as
`(chưa chọn)`. The round number in the title tells you which version the feedback is
about; when it is lower than the draft's current round, say so before acting on it. With
`lang="en"` the headings read "Feedback round N on proposal ...", "Verdict", "Note",
"Answers" and "(not answered)".
