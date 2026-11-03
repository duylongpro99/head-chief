# Page system

The page is a printed booklet: paper, ink, one red, serif titles, a narrow measure and
generous space. Everything here is implemented in `../assets/paper-pencil.css`; this
file explains what each part is for so you can map an existing page onto it.

## Tokens

| Token | Value | Use |
|---|---|---|
| `--paper` | `#faf9f6` | Page background. Plates use a slightly warmer `#f6f1e6`. |
| `--ink` | `#21201f` | Body text, headings, button outlines. |
| `--ink-2` | `#57534f` | Lede, captions, metadata, footer. About 7:1 on paper. |
| `--red` | `#933323` | Links, plate numerals, focus ring, broken or failed things. |
| `--green` | `#2f6b3a` | Only "holds", "passes", "done". |
| `--rule` | `#dcd8d0` | Section top borders and the 1px hairline around images. |
| `--code` | `#f2efe8` | Code blocks and quiet panels. |

Do not add accent colours for variety. When a page needs a second meaning (warning,
new), say it in words or with a drawn mark before reaching for another hue.

## Type

| Role | Face | Size and weight |
|---|---|---|
| h1 | `--serif` (Cutive Mono) | `clamp(2.4rem, 7vw, 4.2rem)`, 400 |
| Section h2 | `--serif` | `clamp(1.8rem, 4vw, 2.4rem)`, 400 |
| Plate title h2 | `--serif` | 1.7rem, 400, inline after the numeral |
| Subtitle | `--italic` (Courier Prime Italic) | body size, `--ink-2` |
| Kicker | `--sans` | body size, 700, `letter-spacing: 0.06em`, lowercase text |
| Body | `--sans` (Nunito Sans) | 1.0625rem / 1.6 |
| Code | `--mono` | 0.8rem / 1.5 in blocks, 0.88em inline |

Headings are never bold. Emphasis inside body text is `<b>` at 700 for the first words
of a list item, and nothing else. Use `text-wrap: pretty` on paragraphs (already set).

Why these faces: the upstream site uses single-stroke letters derived from Hershey's
public-domain pen fonts. Cutive Mono has the same thin, typewriter-like strokes; Courier
Prime Italic gives the slanted handwritten-caption feel; Nunito Sans is monoline and calm.
If the project already ships a thin typewriter serif or a monoline sans, use it instead.

## Layout

- `main`: max 1120px, centred, `padding: 48px var(--gutter) 72px`; gutter
  `clamp(16px, 4vw, 48px)` keeps a 16px edge on phones.
- Text blocks: `max-width: var(--measure)` (46rem). Only the plate grid and code rows
  use the full column.
- Vertical rhythm: 48px title to plates, 56px between plate rows, 88px before a major
  section, 56px between subsections, 80px before the footer.
- Each section starts with `border-top: 1px solid var(--rule)` and 24–32px padding. That
  rule is the only divider; there are no boxes around sections.

## Components (class names in the CSS)

- **Title block** `.top > .kicker + h1 + .lede + .repo`. The kicker names the series or
  product in lowercase ("statechart art"). The lede is one or two plain sentences.
- **Plate grid** `.plates > figure.plate`. `auto-fit` with a 480px minimum, so two plates
  side by side on desktop and one on phones. Each plate is square.
- **Caption** `figcaption > span.num + h2 + p.sub + p`. Numerals are roman (I, II, III),
  red, in the serif. Subtitle in italic. The last paragraph says what the drawing shows
  in one or two sentences, in the reader's words.
- **Ruled section** `.section > h2 + p`. For "how it was made", install steps, FAQ.
- **Steps** `ol.steps > li > b + text`. Bold lead words ending with a full stop.
- **Panel** `.panel > h3 + p`. Cream background, no border; for an aside or definition.
- **Rules list** `ul.rules > li.holds|li.broken > span.mark + text + code`. Green tick or
  red cross drawn by CSS; the identifier in `code` after the sentence.
- **Code row** `.row > figure > pre + figcaption`. Two columns, one below 720px.
- **Buttons** `.button` (ink outline) and `.button.primary` (ink fill). Square. Use them
  only for real actions such as download or install; links stay red text.
- **Footer** `.foot`. A rule, then one or two lines in `--ink-2`.

Mapping an existing page: a hero becomes the title block; a feature grid becomes plates
(one drawing per feature) or a steps list; a terminal demo becomes a `pre` in a row with
its caption; testimonials become a quiet panel or are kept as plain quoted paragraphs;
pricing cards become a two-column row of panels with the prices in the serif.

## Voice

Plain, short, concrete sentences, as if explaining to a friend. Lowercase kickers and
subtitles. No marketing superlatives, no exclamation marks. Name things by what they do
("you pay", "the barista starts"), not by jargon. Only rewrite copy when asked.

## Responsive and accessibility

- Check at 390px and 1280px. Nothing may scroll sideways; long URLs use
  `overflow-wrap: anywhere` (already on `.repo`).
- Inline SVG plates carry `role="img"` with `<title>` and `<desc>` that list the states
  and steps, so the structure is available without the picture.
- Focus rings are the red 2px outline. Keep link underlines.
- Minimum text contrast 4.5:1. `--ink-2` on `--paper` and on `--code` both pass.

## Night paper (only when the host requires dark mode)

The style is light by design. If a host forces a dark theme, swap tokens rather than
inverting drawings, and keep plates on their own light paper so the pencil still reads:

```css
:root[data-theme="dark"] { --paper: #1f1d1b; --ink: #ece7dd; --ink-2: #b4ada2; --red: #d9705e;
  --green: #7fb489; --rule: #3a3632; --code: #2a2724; color-scheme: dark; }
```
