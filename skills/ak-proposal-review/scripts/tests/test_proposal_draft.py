"""Run from the skill directory: python3 -m unittest discover -s scripts/tests"""
import contextlib
import io
import re
import sys
import tempfile
import unittest
from pathlib import Path

SKILL = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SKILL / "scripts"))
import proposal_draft  # noqa: E402

TEMPLATE = (SKILL / "assets" / "proposal-template.html").read_text(encoding="utf-8")


def filled() -> str:
    """The shipped template with every placeholder and template note resolved."""
    text = TEMPLATE.replace("{{slug}}", "demo-proposal")
    text = re.sub(r"<!--\s*TEMPLATE.*?-->\n?", "", text, flags=re.S)
    return re.sub(r"\{\{[^}]*\}\}", "x", text)


class ProposalDraftTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = Path(self.dir.name) / "proposal-demo.html"

    def run_tool(self, *args, text=None):
        if text is not None:
            self.path.write_text(text, encoding="utf-8")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = proposal_draft.main([args[0], str(self.path), *args[1:]])
        return code, out.getvalue()

    def test_filled_template_passes(self):
        code, out = self.run_tool("check", text=filled())
        self.assertEqual(code, 0, out)
        self.assertNotIn("FAIL", out)
        self.assertIn("NOT RUN  rendering", out)

    def test_untouched_template_fails_on_leftovers(self):
        code, out = self.run_tool("check", text=TEMPLATE)
        self.assertEqual(code, 1)
        self.assertRegex(out, r"FAIL\s+template leftovers")

    def test_duplicate_id_is_caught_but_data_id_is_not_an_id(self):
        code, out = self.run_tool("check", text=filled())
        self.assertRegex(out, r"PASS\s+unique id")  # data-id="context" next to id="context"
        code, out = self.run_tool("check", text=filled().replace('<section id="design">', '<section id="context">'))
        self.assertEqual(code, 1)
        self.assertRegex(out, r"FAIL\s+unique id: duplicate id: context")

    def test_broken_link_unclosed_tag_and_remote_font(self):
        text = filled().replace('href="#design"', 'href="#gone"', 1)
        self.assertRegex(self.run_tool("check", text=text)[1], r"FAIL\s+internal links: line \d+: #gone")
        text = filled().replace("</ol>\n</header>", "</header>", 1)
        self.assertRegex(self.run_tool("check", text=text)[1], r"FAIL\s+tag nesting")
        text = filled().replace("<style>", '<link rel="stylesheet" href="https://fonts.example/css"><style>', 1)
        self.assertRegex(self.run_tool("check", text=text)[1], r"FAIL\s+self-contained")

    def test_question_needs_one_recommended_option(self):
        code, out = self.run_tool("check", text=filled().replace('<label class="rec">', "<label>"))
        self.assertEqual(code, 1)
        self.assertRegex(out, r"FAIL\s+question blocks: .*recommended")

    def test_final_requires_no_open_question(self):
        code, out = self.run_tool("check", "--final", text=filled())
        self.assertEqual(code, 1)
        self.assertIn("--final: 1 question block(s) are still open", out)

    def test_forbid_and_expect(self):
        code, out = self.run_tool("check", "--forbid", "review-core", "--expect", "data-round-label=2", text=filled())
        self.assertEqual(code, 1)
        self.assertRegex(out, r"FAIL\s+old wording: \"review-core\" still appears")
        self.assertNotIn("data-round-label\" appears", out)

    def test_page_logic_reading_a_missing_id_fails(self):
        code, out = self.run_tool("check", text=filled().replace('id="res-note"', 'id="renamed"'))
        self.assertEqual(code, 1)
        self.assertRegex(out, r"FAIL\s+script matches page: .*#res-note")

    def test_new_round_saves_a_copy_and_raises_every_number(self):
        code, out = self.run_tool("new-round", text=filled())
        self.assertEqual(code, 0, out)
        saved = self.path.with_name("proposal-demo.versions") / "v1.html"
        self.assertEqual(saved.read_text(encoding="utf-8"), filled())
        text = self.path.read_text(encoding="utf-8")
        self.assertIn('data-round="2"', text)
        self.assertEqual(text.count("<span data-round-label>2</span>"), 2)
        code, out = self.run_tool("check")
        self.assertRegex(out, r"FAIL\s+changes and locked lists")  # round 2 must answer the feedback
        self.assertRegex(out, r"PASS\s+round number")

    def test_stale_visible_label_blocks_new_round(self):
        text = filled().replace("<span data-round-label>1</span>", "<span data-round-label>7</span>", 1)
        self.assertRegex(self.run_tool("check", text=text)[1], r"FAIL\s+round number")
        with self.assertRaises(SystemExit):
            self.run_tool("new-round")
        self.assertFalse(self.path.with_name("proposal-demo.versions").exists())

    def test_backup_keeps_the_round(self):
        code, out = self.run_tool("backup", text=filled())
        self.assertEqual(code, 0)
        copies = list(self.path.with_name("proposal-demo.versions").glob("v1-wip-*.html"))
        self.assertEqual(len(copies), 1)
        self.assertEqual(self.path.read_text(encoding="utf-8"), filled())


if __name__ == "__main__":
    unittest.main()
