---
name: ui-paper-pencil-design
description: Style web pages and draw inline-SVG illustrations in a "paper and pencil" storybook look — warm paper, ink type, square corners, one meaningful red, hand-wobbled ink lines and pastel coloured-pencil fills, with diagrams drawn as objects from the subject's world. Use when the user asks for this paper/pencil, storybook, hand-drawn editorial or statechart-art style on a landing page, docs page, explainer or diagram. Not for general UI art direction without this style (frontend design skill), brand identity or logos (design skill), or raster image generation (AI image skill).
---

# Paper and pencil design

Turn a page, or a diagram on it, into a quiet printed-book page with code-drawn
coloured-pencil plates. The look is modelled on
[kevintngo/statechart-art](https://kevintngo.github.io/statechart-art/) (MIT): the page
is plain so the drawings carry it, and every drawing is the content itself (a state is a
ticket, a region is a tinted panel, a failure is a red trace), never decoration.

The consumer is whoever builds the page. The reader of the result is a person on a phone
or a laptop who should feel they are holding a well-made booklet.

## Activation boundary

Use for: restyling an existing page into this look, building a new page in it, drawing an
SVG diagram or spot illustration in it, or checking a page against it.

Hand off: general art direction in another style goes to the installed frontend design
skill; logos and brand systems to the design skill; photographic or painted raster art to
the AI image skill; component-library theming (shadcn, MUI) to the UI styling skill.
This skill can be combined with them only when the user wants this style.

## Authority

- Restyle, do not rewrite. Keep the page's text, links, scripts, forms, analytics hooks,
  metadata and behaviour. Change copy only when the user asks; then follow the voice notes
  in `references/page-system.md`.
- Edit only the files the user names (or the obvious page they point at). Ask before
  deleting assets or replacing a framework.
- Do not copy the upstream "Kevin Serif / Kevin Sans" fonts or its drawings: they are the
  original author's personal faces and art. Use the open substitutes below and draw new
  illustrations for the user's subject.

## The invariants

These are what make the style read as this style. A result that breaks one should say
why.

1. **Paper and ink.** Background `--paper #faf9f6`, text `--ink #21201f`, secondary
   `--ink-2 #57534f`, hairlines `--rule #dcd8d0`, quiet panels `--code #f2efe8`. Set the
   background explicitly on `html`/`body`.
2. **One red that means something.** `--red #933323` marks links, plate numerals, focus
   rings and things that break or fail; `--green #2f6b3a` marks only things that hold or
   pass. No other saturated colour in page chrome. Pastels live inside drawings only.
3. **Flat and square.** `border-radius: 0` on chrome, no blurred shadows, no gradients,
   no glass, no cards. Images and drawings get a 1px hairline (`box-shadow: 0 0 0 1px
   var(--rule)`). Sections are separated by a top rule and space.
4. **Book typography.** Headings in a serif at weight 400; subtitles in italic serif;
   body in a calm sans at about 17px/1.6; a small bold letter-spaced kicker above the
   title. Text measure at most 46rem inside a 1120px column.
5. **Editorial order.** Kicker, title, lede, a grid of captioned plates, a "how it was
   made" section, then a ruled footer. Captions: red roman numeral, serif title, italic
   subtitle, one plain sentence.
6. **Drawings are the content.** Pick the subject's own world, map each kind of node to
   one object from it, and draw the real structure (every state, step and label). Labels
   sit on clean paper, arrows stop short of their targets, ink lines wobble a little,
   fills show pencil grain, and red appears only where the meaning is red.
7. **Drawn, not borrowed.** No emoji, icon fonts or stock images in the styled area;
   draw marks (✓ ✗ as text glyphs are fine) and spot art in the same pencil SVG.

Fonts (Google Fonts, all OFL): display and headings **Cutive**, italic subtitles and
captions **Courier Prime Italic**, body and UI **Nunito Sans**, code `ui-monospace`.
Keep the fallbacks in `assets/paper-pencil.css` so the page still reads with fonts off.

## Workflow

1. Inventory the target: content blocks, links, scripts, existing CSS, where images or
   diagrams already are, and any host rules (for example a host that requires dark mode;
   use the night-paper variant in `references/page-system.md`).
2. Bring in `assets/paper-pencil.css` (inline it for a single-file page, or link it).
   Map the existing markup onto its classes rather than inventing parallel ones.
3. Re-order the page into the editorial structure where the content allows; keep any
   section the page needs (install commands, pricing, FAQ) and style it with the same
   rules, panels and lists.
4. Draw plates and spot art. Paste the `<defs>` from `assets/pencil-defs.svg` once per
   page, then follow `references/illustration-svg.md` for the object mapping, strokes,
   fills, labels and composition. `assets/example.html` is a working reference page.
5. Verify (below), fix, and report.

## Definition of done

- `python3 scripts/check_style.py <page files>` reports no findings, or every remaining
  finding is listed in the report with the reason it stays (for example a third-party
  embed with its own radius).
- The page is rendered and looked at, at about 390px and 1280px wide: no horizontal
  scroll, fonts loaded, SVG filters visible (wobble and grain, not blank or blurred
  shapes), every label readable on clean paper, text contrast at least 4.5:1.
- Every drawing shows the real structure it claims to (count states, steps and labels
  against the source) and each red element has a meaning the caption or legend states.
- The report names the files changed, what was kept unchanged, and anything not verified
  (for example no browser available to render).

## Resources

- `references/page-system.md` — tokens, type scale, layout, component markup, copy voice,
  responsive and accessibility notes, night-paper variant. Read before styling a page.
- `references/illustration-svg.md` — object mapping, ink and pencil technique, palette,
  labels, arrows, characters, plate composition, performance. Read before drawing.
- `assets/paper-pencil.css` — tokens, base styles and components.
- `assets/pencil-defs.svg` — SVG filters and patterns (wobble, grain, pencil fill, hatch,
  arrowheads).
- `assets/example.html` — a complete page with one plate, to copy from and to sanity-check
  rendering.
- `scripts/check_style.py` — flags rounded corners, blurred shadows, gradients, emoji and
  off-palette saturated colours in page CSS. Python 3.9+, standard library, macOS/Linux;
  tests in `scripts/tests/`.
