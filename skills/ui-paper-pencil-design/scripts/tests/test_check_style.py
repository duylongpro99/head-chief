"""Tests for check_style.py and for the bundled assets. Run from the skill directory:
python3 -m unittest discover -s scripts/tests
"""
import importlib.util
import re
import tempfile
import unittest
from pathlib import Path

SKILL = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("check_style", SKILL / "scripts" / "check_style.py")
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)


def rules_for(content, suffix=".html"):
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / f"page{suffix}"
        p.write_text(content, encoding="utf-8")
        return [rule for _, rule, _ in cs.check(p)]


class CheckStyleTests(unittest.TestCase):
    def test_bundled_assets_are_clean(self):
        for name in ("paper-pencil.css", "example.html"):
            with self.subTest(name=name):
                self.assertEqual(cs.check(SKILL / "assets" / name), [])

    def test_example_defs_match_shared_defs(self):
        grab = lambda p: re.search(r"<defs>.*?</defs>", p.read_text(), re.S).group(0)
        self.assertEqual(grab(SKILL / "assets" / "example.html"), grab(SKILL / "assets" / "pencil-defs.svg"))

    def test_rounded_corner(self):
        self.assertEqual(rules_for(".card{border-radius:12px}", ".css"), ["rounded-corner"])
        self.assertEqual(rules_for("*{border-radius:0}", ".css"), [])

    def test_shadows(self):
        self.assertEqual(rules_for("a{box-shadow:0 4px 12px rgba(0,0,0,.2)}", ".css"), ["blurred-shadow"])
        self.assertEqual(rules_for("img{box-shadow:0 0 0 1px var(--rule)}", ".css"), [])
        self.assertEqual(rules_for("img{box-shadow:none}", ".css"), [])

    def test_gradient_and_glass(self):
        self.assertEqual(rules_for("b{background:linear-gradient(#fff,#eee)}", ".css"), ["gradient"])
        self.assertEqual(rules_for("b{backdrop-filter:blur(8px)}", ".css"), ["glass"])

    def test_colours(self):
        self.assertEqual(rules_for("a{color:#3b82f6}", ".css"), ["off-palette"])
        self.assertEqual(rules_for("a{color:rgb(59,130,246)}", ".css"), ["off-palette"])
        self.assertEqual(rules_for("a{color:#933323;background:#faf9f6;border-color:#dcd8d0}", ".css"), [])

    def test_svg_presentation_colours_are_not_page_css(self):
        html = '<svg><rect fill="#f2b9c2" style="fill:#c4dbe8"/></svg><p style="color:#21201f">ok</p>'
        self.assertEqual(rules_for(html), [])

    def test_inline_style_outside_svg_is_checked(self):
        self.assertEqual(rules_for('<div style="border-radius: 8px">x</div>'), ["rounded-corner"])

    def test_emoji(self):
        self.assertEqual(rules_for("<p>Fast \U0001F680</p>"), ["emoji"])
        self.assertEqual(rules_for("<p>✓ holds</p><code>\U0001F680</code>"), [])

    def test_exit_codes(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "a.css"
            p.write_text("a{border-radius:4px}")
            self.assertEqual(cs.main([str(p)]), 1)
            self.assertEqual(cs.main([str(p), "--warn-only"]), 0)
            self.assertEqual(cs.main([str(Path(d) / "missing.css")]), 2)


if __name__ == "__main__":
    unittest.main()
