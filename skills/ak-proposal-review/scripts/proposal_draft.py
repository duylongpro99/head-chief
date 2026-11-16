#!/usr/bin/env python3
"""Mechanical checks and round bookkeeping for a local HTML proposal draft.

Subcommands:
  check <draft.html> [--forbid TEXT ...] [--expect TEXT=N ...] [--final]
  backup <draft.html>       copy the draft before an edit that stays in the current round
  new-round <draft.html>    copy the draft, then raise the round number everywhere it is stored

Standard library only. `check` runs `node --check` on inline scripts when node is on PATH
and reports the step as not run otherwise. Works on macOS, Linux and Windows.
"""
from __future__ import annotations

import argparse
import datetime
import re
import shutil
import subprocess
import sys
import tempfile
from html.parser import HTMLParser
from pathlib import Path

# Tags whose open/close pairs must nest correctly. `p`, `td`, `dt` and friends are left
# out because HTML lets them close implicitly.
STRICT = {
    "html", "head", "body", "main", "header", "footer", "section", "div", "span", "a", "b",
    "ol", "ul", "li", "dl", "table", "tr", "pre", "code", "label", "button", "output",
    "h1", "h2", "h3", "h4", "small", "strong", "textarea", "script", "style",
}
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
ROUND_ATTR_RE = re.compile(r'(<body\b[^>]*\bdata-round=")(\d+)(")')
ROUND_LABEL_RE = re.compile(r"(<span\b[^>]*\bdata-round-label[^>]*>)\s*(\d+)\s*(</span>)")
EXTERNAL_CSS_RE = re.compile(r"@import|url\(\s*['\"]?(?:https?:)?//", re.I)
ELEMENT_ID_REF_RE = re.compile(r"getElementById\(\s*['\"]([^'\"]+)['\"]\s*\)")


class Draft(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[tuple[str, int, dict]] = []
        self.nesting: list[str] = []
        self.ids: list[str] = []
        self.fb: list[dict] = []
        self.anchors: list[tuple[str, int]] = []
        self.external: list[str] = []
        self.body: dict = {}
        self.round_labels: list[str] = []
        self.questions: list[dict] = []
        self.sections: list[dict] = []
        self.fields: list[dict] = []
        self.scripts: list[dict] = []
        self.styles: list[str] = []
        self._text_target: list | None = None

    def _inside(self, key: str) -> dict | None:
        for _, _, info in reversed(self.stack):
            if key in info:
                return info[key]
        return None

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        line = self.getpos()[0]
        classes = a.get("class", "").split()
        info: dict = {}
        if "id" in a:
            self.ids.append(a["id"])
        if tag == "body":
            self.body = a
        if tag == "section":
            info["section"] = {"id": a.get("id", ""), "line": line, "fb": 0}
            self.sections.append(info["section"])
        if "fb" in classes:
            self.fb.append({"id": a.get("data-id", ""), "title": a.get("data-title", ""), "line": line})
            section = self._inside("section")
            if section:
                section["fb"] += 1
        if "q" in classes:
            info["q"] = {"label": a.get("data-label", ""), "line": line, "names": set(), "radios": 0, "rec": 0, "fields": 0}
            self.questions.append(info["q"])
        question = self._inside("q")
        if tag == "label" and "rec" in classes and question:
            question["rec"] += 1
        if tag == "input" and a.get("type") == "radio" and question:
            question["names"].add(a.get("name", ""))
            question["radios"] += 1
        if "data-field" in a:
            self.fields.append({"id": a.get("id", ""), "label": a["data-field"], "line": line})
            if question:
                question["fields"] += 1
        if tag == "a" and a.get("href", "").startswith("#"):
            self.anchors.append((a["href"][1:], line))
        if tag == "link" and a.get("href"):
            self.external.append(f"line {line}: <link href={a['href']}>")
        if tag in ("script", "img", "iframe", "video", "audio", "source") and a.get("src"):
            if tag == "script" or re.match(r"(?:https?:)?//", a["src"]):
                self.external.append(f"line {line}: <{tag} src={a['src']}>")
        if EXTERNAL_CSS_RE.search(a.get("style", "")):
            self.external.append(f"line {line}: inline style loads a remote resource")
        if "data-round-label" in a:
            info["label_text"] = []
            self._text_target = info["label_text"]
        if tag == "script":
            info["script"] = {"id": a.get("id", ""), "line": line, "text": []}
            self.scripts.append(info["script"])
            self._text_target = info["script"]["text"]
        if tag == "style":
            info["style_text"] = []
            self._text_target = info["style_text"]
        if tag in STRICT:
            self.stack.append((tag, line, info))

    def handle_endtag(self, tag):
        if tag not in STRICT:
            return
        line = self.getpos()[0]
        if not self.stack:
            self.nesting.append(f"line {line}: </{tag}> has no opening tag")
            return
        open_tag, open_line, info = self.stack[-1]
        if open_tag != tag:
            if any(t == tag for t, _, _ in self.stack):
                while self.stack and self.stack[-1][0] != tag:
                    t, l, _ = self.stack.pop()
                    self.nesting.append(f"line {l}: <{t}> is not closed before </{tag}> on line {line}")
                open_tag, open_line, info = self.stack[-1]
            else:
                self.nesting.append(f"line {line}: </{tag}> has no opening tag")
                return
        self.stack.pop()
        if "label_text" in info:
            self.round_labels.append("".join(info["label_text"]).strip())
        if "style_text" in info:
            self.styles.append("".join(info["style_text"]))
        if "label_text" in info or "script" in info or "style_text" in info:
            self._text_target = None

    def handle_data(self, data):
        if self._text_target is not None:
            self._text_target.append(data)

    def close(self):
        super().close()
        for tag, line, _ in self.stack:
            self.nesting.append(f"line {line}: <{tag}> is never closed")


def duplicates(values: list[str]) -> list[str]:
    seen, dup = set(), []
    for v in values:
        if v in seen and v not in dup:
            dup.append(v)
        seen.add(v)
    return dup


def node_check(scripts: list[dict]) -> tuple[str, str]:
    node = shutil.which("node")
    if not node:
        return "skip", "node is not on PATH, so script syntax was not checked"
    errors = []
    for i, s in enumerate(scripts):
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as fh:
            fh.write("".join(s["text"]))
            tmp = Path(fh.name)
        try:
            run = subprocess.run([node, "--check", str(tmp)], capture_output=True, text=True)
        finally:
            tmp.unlink(missing_ok=True)
        if run.returncode != 0:
            detail = (run.stderr.strip().splitlines() or ["syntax error"])[-1]
            errors.append(f"script #{i + 1} (line {s['line']}): {detail}")
    return ("fail", "; ".join(errors)) if errors else ("pass", f"{len(scripts)} script block(s) parse")


def check(path: Path, forbid: list[str], expect: list[str], final: bool) -> int:
    source = path.read_text(encoding="utf-8")
    d = Draft()
    d.feed(source)
    d.close()
    results: list[tuple[str, str, str]] = []

    def add(name: str, problems: list[str] | str | None, ok: str = "") -> None:
        if isinstance(problems, str):
            problems = [problems]
        if problems:
            results.append(("FAIL", name, "; ".join(problems)))
        else:
            results.append(("PASS", name, ok))

    left = sorted(set(re.findall(r"\{\{[^}]*\}\}", source)))
    notes = len(re.findall(r"<!--\s*TEMPLATE", source))
    problems = [f"{len(left)} unfilled placeholder(s), first: {left[0]}"] if left else []
    if notes:
        problems.append(f"{notes} TEMPLATE comment(s) still in the file")
    add("template leftovers", problems, "none")

    add("tag nesting", d.nesting[:8], "open and close tags pair up")

    dup = duplicates(d.ids)
    add("unique id", [f"duplicate id: {', '.join(dup)}"] if dup else None, f"{len(d.ids)} ids")

    fb_problems = [f"duplicate data-id: {', '.join(duplicates([f['id'] for f in d.fb]))}"] if duplicates([f["id"] for f in d.fb]) else []
    fb_problems += [f"line {f['line']}: feedback box needs data-id and data-title" for f in d.fb if not f["id"] or not f["title"]]
    if not d.fb:
        fb_problems.append("the page has no feedback box")
    add("feedback boxes", fb_problems, f"{len(d.fb)} box(es)")

    idset = set(d.ids)
    broken = [f"line {line}: #{target}" for target, line in d.anchors if target not in idset]
    add("internal links", broken[:8], f"{len(d.anchors)} link(s) resolve")

    external = list(d.external)
    external += ["a <style> block loads a remote resource" for s in d.styles if EXTERNAL_CSS_RE.search(s)]
    add("self-contained", external, "no stylesheet, script, font or image is loaded from outside the file")

    round_text = d.body.get("data-round", "")
    slug = d.body.get("data-slug", "")
    meta = []
    if not round_text.isdigit() or int(round_text) < 1:
        meta.append("body data-round must be a positive integer")
    if not SLUG_RE.match(slug):
        meta.append("body data-slug must be kebab-case")
    if not d.body.get("data-name", "").strip():
        meta.append("body data-name is empty")
    if not d.round_labels:
        meta.append("no visible data-round-label element")
    wrong = [t for t in d.round_labels if t != round_text]
    if wrong:
        meta.append(f"visible round label(s) {wrong} differ from data-round {round_text}")
    add("round number", meta, f"round {round_text}: storage key, export title and download name derive from it, {len(d.round_labels)} visible label(s) match")

    q_problems = []
    names: list[str] = []
    for q in d.questions:
        where = f"question on line {q['line']}"
        if not q["label"].strip():
            q_problems.append(f"{where} needs data-label")
        if len(q["names"]) > 1 or "" in q["names"]:
            q_problems.append(f"{where} must use exactly one radio name")
        names += sorted(q["names"])
        if q["radios"] and q["rec"] != 1:
            q_problems.append(f"{where} must mark exactly one option as recommended (label class \"rec\"), found {q['rec']}")
        if not q["radios"] and not q["fields"]:
            q_problems.append(f"{where} has nothing to answer with")
    if duplicates(names):
        q_problems.append(f"radio name reused across questions: {', '.join(duplicates(names))}")
    if final and d.questions:
        q_problems.append(f"--final: {len(d.questions)} question block(s) are still open")
    add("question blocks", q_problems, f"{len(d.questions)} open question(s)")

    field_problems = [f"line {f['line']}: data-field element needs an id and a label" for f in d.fields if not f["id"] or not f["label"].strip()]
    core = [s for s in d.scripts if s["id"] == "review-core"]
    if len(core) != 1:
        field_problems.append("expected exactly one <script id=\"review-core\">")
    for s in d.scripts:
        if s["id"] == "review-core":
            continue
        for ref in ELEMENT_ID_REF_RE.findall("".join(s["text"])):
            if ref not in idset:
                field_problems.append(f"script on line {s['line']} reads #{ref}, which is not in the page")
    add("script matches page", field_problems, f"{len(d.fields)} field(s), every id the page logic reads exists")

    if round_text.isdigit() and int(round_text) >= 2:
        missing = [i for i in ("changes", "locked") if i not in idset]
        add("changes and locked lists", [f"round {round_text} needs an element with id \"{i}\"" for i in missing], "present")

    status, detail = node_check(d.scripts)
    results.append(({"pass": "PASS", "fail": "FAIL", "skip": "NOT RUN"}[status], "script syntax", detail))

    text_problems = []
    for needle in forbid:
        n = source.count(needle)
        if n:
            text_problems.append(f"\"{needle}\" still appears {n} time(s)")
    for item in expect:
        needle, _, want = item.rpartition("=")
        if not needle or not want.isdigit():
            text_problems.append(f"--expect needs TEXT=N, got \"{item}\"")
        elif source.count(needle) != int(want):
            text_problems.append(f"\"{needle}\" appears {source.count(needle)} time(s), expected {want}")
    if forbid or expect:
        add("old wording", text_problems, f"{len(forbid)} forbidden and {len(expect)} counted string(s) as expected")

    for status, name, detail in results:
        print(f"{status:8} {name}: {detail}")
    bare = [s["id"] or f"line {s['line']}" for s in d.sections if not s["fb"]]
    if bare:
        print(f"NOTE     sections without a feedback box: {', '.join(bare)}")
    print("NOT RUN  rendering and clicks in a real browser: this script cannot see the page")
    failed = sum(1 for r in results if r[0] == "FAIL")
    print(f"\n{'FAILED' if failed else 'OK'}: {failed} failing check(s) in {path}")
    return 1 if failed else 0


def read_round(source: str) -> int:
    found = ROUND_ATTR_RE.findall(source)
    if len(found) != 1:
        raise SystemExit(f"expected exactly one <body data-round=\"N\">, found {len(found)}")
    return int(found[0][1])


def versions_dir(path: Path) -> Path:
    return path.with_name(path.stem + ".versions")


def save_copy(path: Path, name: str) -> Path:
    target = versions_dir(path) / name
    if target.exists():
        raise SystemExit(f"{target} already exists; refusing to overwrite a saved version")
    target.parent.mkdir(exist_ok=True)
    shutil.copy2(path, target)
    return target


def backup(path: Path) -> int:
    current = read_round(path.read_text(encoding="utf-8"))
    stamp = datetime.datetime.now().strftime("%y%m%d-%H%M%S")
    print(f"saved {save_copy(path, f'v{current}-wip-{stamp}.html')}")
    return 0


def new_round(path: Path) -> int:
    source = path.read_text(encoding="utf-8")
    current = read_round(source)
    labels = ROUND_LABEL_RE.findall(source)
    if not labels:
        raise SystemExit("no <span data-round-label>N</span> found; add the visible round label first")
    stale = [n for _, n, _ in labels if int(n) != current]
    if stale:
        raise SystemExit(f"visible round label(s) {stale} differ from data-round {current}; fix them before starting a new round")
    saved = save_copy(path, f"v{current}.html")
    nxt = str(current + 1)
    source = ROUND_ATTR_RE.sub(lambda m: m.group(1) + nxt + m.group(3), source)
    source = ROUND_LABEL_RE.sub(lambda m: m.group(1) + nxt + m.group(3), source)
    path.write_text(source, encoding="utf-8")
    print(f"saved {saved}")
    print(f"round {current} -> {nxt} in {path} (data-round and {len(labels)} visible label(s))")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    c = sub.add_parser("check", help="run every mechanical check and exit 1 on any failure")
    c.add_argument("draft", type=Path)
    c.add_argument("--forbid", action="append", default=[], metavar="TEXT", help="wording from an earlier round that must be gone")
    c.add_argument("--expect", action="append", default=[], metavar="TEXT=N", help="wording that must appear exactly N times")
    c.add_argument("--final", action="store_true", help="also require that no question block is left")
    for name, text in (("backup", "save a copy without changing the round"), ("new-round", "save a copy and raise the round number")):
        s = sub.add_parser(name, help=text)
        s.add_argument("draft", type=Path)
    args = parser.parse_args(argv)
    if not args.draft.is_file():
        raise SystemExit(f"{args.draft} is not a file")
    if args.command == "check":
        return check(args.draft, args.forbid, args.expect, args.final)
    return backup(args.draft) if args.command == "backup" else new_round(args.draft)


if __name__ == "__main__":
    sys.exit(main())
