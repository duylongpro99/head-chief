# Illustration in SVG

Plates and spot art are inline SVG that look drawn with a pen and coloured pencils on
paper. The filters and patterns are in `../assets/pencil-defs.svg`; a full worked plate
is in `../assets/example.html`.

## 1. Decide what to draw before drawing

A plate always shows real structure: a state machine, a pipeline, a flow, a timeline, an
architecture, or a before/after. Write the structure down first (every node, edge and
label), then draw it. Count them again on the finished plate.

Then choose the subject's world and give each kind of node one object from it:

| Structure | Upstream boba example | Pattern to reuse |
|---|---|---|
| Simple state or step | order ticket pinned up, paper tag | a slip of paper the subject actually uses |
| Parent or group | the shop window with notes taped on | a container from the world: window, drawer, notebook page, tray |
| Parallel regions | two tinted panels side by side, dashed divider | two surfaces in two pastel tints, one per actor |
| Transition | red thread between pins, ink arrow | thread, string, ink line; italic label beside it |
| Failure or broken rule | red-traced path, red double outline, "rule broken" stamp | red only on that path and state, plus a legend |
| Start | small ink ring with a red dot | same |

For a CLI or developer tool, the world might be a desk: commands on index cards, a
terminal as a notebook page, a pipeline as cards clipped to a string. Keep it to one
world per plate.

## 2. Layers, back to front

1. **Paper**: a full-size rect `fill="#f6f1e6" filter="url(#pp-paper)"`.
2. **Clean paper under objects**: the shape filled `#fbf7ee`, no filter. Keeps text crisp.
3. **Pencil tint**: the same shape in a pastel with `filter="url(#pp-pencil)"`. The
   filter breaks the colour with paper tooth and pushes it slightly past the outline.
4. **Ink, pass one**: the same shape, `fill="none"`, ink stroke, `filter="url(#pp-ink)"`.
5. **Ink, pass two**: again with `filter="url(#pp-ink-b)"` at opacity 0.4–0.5. Two
   passes that wander differently are what makes a line feel hand-drawn.
6. **Text**, with no filter, on top.

Define each repeated shape once in the plate's `<defs>` and draw it with `<use href>`
for each layer, as the example does with `#tag`.

## 3. Ink

- Colour `#1d1a1e`, `stroke-width` 2–2.6 in a 1080 viewBox, `stroke-linecap="round"`,
  `stroke-linejoin="round"`. Thin details (steam, hatching) 1.2–1.6.
- Lines are slightly imperfect, never sketchy: no scribble loops, no visible jitter at
  rest size. If a line looks like a vector stroke, add the second pass; if it looks
  shaky, lower the displacement `scale`.
- Hatch shadows and texture with `fill="url(#pp-hatch)"` or `#pp-crosshatch`; rotate by
  changing `patternTransform`. Under objects, use a hatched ellipse, not a blur.
- Ground lines: one thin ink line the width of the scene, objects standing on it.

## 4. Colour inside drawings

Ink plus soft pastels, taken from the subject. The upstream boba palette:

| Name | Hex | Name | Hex |
|---|---|---|---|
| cream (tag) | `#f7eedb` | sky | `#c4dbe8` |
| ice | `#dcebf1` | blush | `#f2b9c2` |
| rose | `#d9727a` | sage | `#9dbb86` |
| ochre | `#e0b04f` | caramel | `#d9ac7c` |
| wood | `#c99b6b` | lilac | `#c6b6de` |
| mint | `#bfe0cf` | tea | `#a8693f` |

Use 3–5 pastels per plate. Plate red for meaning is `#a8443b` (lines, arrowheads,
outline of the broken state) with `#f2b9c2` as the broken state's tint. Parallel regions
get one tint each (sky and blush), and a guard that waits on the other region is written
in that region's colour.

## 5. Text on plates

- States: `--serif` (Cutive Mono) at 38–44 in a 1080 viewBox. Step labels: `--italic`
  at 32–36. Kicker 28–30, title 96–112, subtitle 34–38. Below about 32 the text is
  unreadable on a phone, where the plate shows at roughly a third of its size.
- Measure before you draw a box: Cutive Mono advances about 0.6 em per character, so a
  label of `n` characters at size `s` is about `0.6 × n × s` wide. Box width = that plus
  at least 30 on each side, plus room for any pin or hole.
- Labels sit on clean paper: put `paint-order="stroke"` with a paper-coloured stroke 10–12
  wide on the label group, or a paper rect behind it. Ink never crosses letters.
- Step labels sit beside their line, not on it, and never inside another object.
- Conditions go in square brackets after the label: `the barista starts [if there are
  pearls]`. Long labels wrap onto a second `<text>` line rather than shrinking.

## 6. Arrows

- Use `marker-end="url(#pp-arrow)"` (or `#pp-arrow-red`), open chevron heads.
- End the path 6–12 units before the target's edge; arrows stop short of what they point
  at. Start them a few units off the source edge too.
- Prefer straight vertical runs and one soft curve for branches. Loops back go round the
  outside of the chart.

## 7. Characters and spot art

Optional, and only from the subject's world. The chibi recipe used upstream: a round
head (circle), two dot eyes, a small pink blush ellipse on each cheek (`#f2b9c2`, opacity
0.7), simple hair as one filled shape, a trapezoid torso in a pastel shirt, stick arms
and legs in ink, white rounded shoes. Props are simple outlined shapes with one tint and
a little hatching. Spot art fills the empty corners and stands on a ground line; it
never covers chart text or lines.

## 8. Composition

- Square plate, `viewBox="0 0 1080 1080"`, about 40 units of margin.
- Title block top left: kicker `series · I`, big title, italic subtitle.
- The chart takes the centre or right two thirds; spot art takes the leftover corners.
- One optional legend box (top right) when red or tints need explaining:
  `the rule` / the rule in italic / a red line sample with "the path we found".
- Leave paper showing. If a plate feels busy, remove props before shrinking the chart.

## 9. Performance and portability

- Paste the `<defs>` once per page; every plate references the same ids.
- SVG filters are costly on very large areas. Filter shapes, not whole 1080 groups, and
  keep the paper filter on one rect. Avoid animating filtered elements.
- Filter output differs slightly between browsers; check Chrome and Safari when both
  matter. If a host strips filters (some email or markdown renderers), export the plate
  to PNG at 2160px and use `<img>` with the same caption.
