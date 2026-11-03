#!/usr/bin/env python3
"""Check HTML/CSS files against the paper-pencil page invariants.

Scans page CSS (.css files, <style> blocks and style="" attributes) for rounded
corners, blurred shadows, gradients, glass effects and saturated colours outside the
palette, and page text for emoji. SVG presentation attributes (fill="...", stroke="...")
are not page CSS and are not checked, so pastels inside drawings are fine.

Usage: check_style.py FILE [FILE ...] [--warn-only]
Exit status: 0 when clean (or --warn-only), 1 when findings exist, 2 on usage errors.
Python 3.9+, standard library only. Tested on macOS and Linux.
"""
import argparse
import re
import sys
from pathlib import Path

# Saturated colours the style allows in page chrome: the meaning red and green, the
# plate red used in SVG text classes, and the night-paper variants.
ALLOWED = ["#933323", "#2f6b3a", "#a8443b", "#b5453a", "#d9705e", "#7fb489"]
CHROMA_LIMIT = 0.18  # (max - min) / 255; paper, ink and greys stay well below it
NEAR = 24  # max per-channel distance to count as an allowed colour

STYLE_BLOCK = re.compile(r"<style\b[^>]*>(.*?)</style>", re.S | re.I)
STYLE_ATTR = re.compile(r"""\sstyle\s*=\s*(["'])(.*?)\1""", re.S | re.I)
SKIP_TEXT = re.compile(r"<(script|style|pre|code)\b.*?</\1>|<!--.*?-->|<[^>]+>", re.S | re.I)
RADIUS = re.compile(r"border(?:-(?:top|bottom|start|end)-(?:left|right|start|end))?-radius\s*:\s*([^;}\"']+)", re.I)
SHADOW = re.compile(r"(?<![-\w])box-shadow\s*:\s*([^;}\"']+)", re.I)
GRADIENT = re.compile(r"(?:repeating-)?(?:linear|radial|conic)-gradient\s*\(", re.I)
GLASS = re.compile(r"backdrop-filter\s*:\s*(?!none)", re.I)
HEX = re.compile(r"#([0-9a-f]{6}|[0-9a-f]{3})\b", re.I)
RGB = re.compile(r"rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)", re.I)
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-⛿️]")
LENGTH = re.compile(r"-?\d*\.?\d+[a-z%]*", re.I)


def css_regions(path, text):
    """Yield (offset, css) pairs for every piece of page CSS in the file."""
    if path.suffix.lower() == ".css":
        yield 0, text
        return
    for m in STYLE_BLOCK.finditer(text):
        yield m.start(1), m.group(1)
    for m in STYLE_ATTR.finditer(text):
        before = text[: m.start()]
        if before.lower().count("<svg") > before.lower().count("</svg>"):
            continue  # inside an SVG drawing
        yield m.start(2), m.group(2)


def to_rgb(token):
    m = HEX.fullmatch(token)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))
    m = RGB.match(token)
    return tuple(int(v) for v in m.groups()) if m else None


def is_allowed(rgb):
    for hexval in ALLOWED:
        ref = to_rgb(hexval)
        if all(abs(a - b) <= NEAR for a, b in zip(rgb, ref)):
            return True
    return False


def shadow_is_blurred(value):
    value = value.strip().lower()
    if value.startswith(("none", "initial", "unset", "inherit")):
        return False
    for layer in re.split(r",(?![^()]*\))", value):
        layer = re.sub(r"\b(?:rgba?|hsla?)\([^)]*\)|#[0-9a-f]+|var\([^)]*\)|inset|[a-z]+(?![\w(])", " ", layer)
        lengths = LENGTH.findall(layer)
        if len(lengths) >= 3 and float(re.match(r"-?\d*\.?\d+", lengths[2]).group()) != 0:
            return True
    return False


def check(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    found = []

    def add(offset, rule, msg):
        found.append((text.count("\n", 0, offset) + 1, rule, msg))

    for base, css in css_regions(path, text):
        for m in RADIUS.finditer(css):
            if any(v not in ("0", "0px", "0%", "0rem", "0em") for v in m.group(1).split()):
                add(base + m.start(), "rounded-corner", f"border-radius {m.group(1).strip()}; the style is square")
        for m in SHADOW.finditer(css):
            if shadow_is_blurred(m.group(1)):
                add(base + m.start(), "blurred-shadow", "use a 1px hairline (0 0 0 1px var(--rule)) instead")
        for m in GRADIENT.finditer(css):
            add(base + m.start(), "gradient", "flat paper and pencil only; no gradients")
        for m in GLASS.finditer(css):
            add(base + m.start(), "glass", "backdrop-filter is not part of the style")
        for m in list(HEX.finditer(css)) + list(RGB.finditer(css)):
            rgb = to_rgb(m.group(0))
            if rgb and (max(rgb) - min(rgb)) / 255 > CHROMA_LIMIT and not is_allowed(rgb):
                add(base + m.start(), "off-palette", f"{m.group(0)} is a saturated colour outside the palette")

    if path.suffix.lower() in (".html", ".htm"):
        visible = SKIP_TEXT.sub(lambda m: " " * len(m.group(0)), text)
        for m in EMOJI.finditer(visible):
            add(m.start(), "emoji", f"U+{ord(m.group(0)):04X}; draw the mark in SVG or use text")
    return sorted(found)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--warn-only", action="store_true", help="always exit 0")
    args = ap.parse_args(argv)
    total = 0
    for path in args.files:
        if not path.is_file():
            print(f"{path}: not a file", file=sys.stderr)
            return 2
        for line, rule, msg in check(path):
            print(f"{path}:{line}: {rule}: {msg}")
            total += 1
    print(f"{total} finding(s) in {len(args.files)} file(s)")
    return 0 if total == 0 or args.warn_only else 1


if __name__ == "__main__":
    sys.exit(main())
