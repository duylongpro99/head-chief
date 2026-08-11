#!/usr/bin/env python3
"""Structural self-validator for the head-chief skill (created in Phase 01, C7).

Run after every phase, before hand-off — it enforces the cross-phase invariants
that prose review misses. All checks are deterministic, read-only, and offline
(so the helper is allowlist-safe; see Phase 10 / C10).

Checks:
  1. Ownership table (references/ledger-protocol.md) assigns exactly ONE writer to
     the frontmatter `status` field (C4/D-α) — and no path row is double-claimed.
  2. Every file named in the SKILL.md Resources table exists on disk.
  3. Each request/track template carries its required frontmatter keys.
  4. No secret-shaped strings (DSNs, KEY=secret assignments) in any skill file.

Usage:
    quick_validate.py        # validate the skill this script ships in
Exit codes: 0 = all checks pass, 1 = one or more failed.
"""

import re
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
LEDGER_PROTOCOL = SKILL_DIR / "references" / "ledger-protocol.md"
SKILL_MD = SKILL_DIR / "SKILL.md"

# Templates that MUST carry these frontmatter keys (stable across every phase).
REQUIRED_FRONTMATTER = {
    "assets/log-request-template.md": ["session", "class", "status", "created"],
    "assets/track-status-template.md": ["session", "status", "created"],
}

# Files scanned for secret-shaped strings (the whole skill surface).
SECRET_SCAN_GLOBS = ("*.md", "references/*.md", "assets/*.md", "scripts/*.py", "evals/*.json")

# A DSN with embedded credentials, or an ALL-CAPS secret key assigned a real value.
DSN_RE = re.compile(r"(postgres|postgresql|mysql|mongodb|redis)://[^\s/]+:[^\s/@]+@", re.I)
SECRET_ASSIGN_RE = re.compile(
    r"\b[A-Z][A-Z0-9_]*(?:PASSWORD|PASSWD|SECRET|TOKEN|DSN|APIKEY|API_KEY)[A-Z0-9_]*\s*[:=]\s*"
    r"([^\s'\"<>#]{6,})"
)
# Values that are obviously placeholders / documentation, not real secrets.
PLACEHOLDER_HINT = re.compile(r"redact|example|placeholder|your[-_]|xxx|changeme|\.\.\.", re.I)


def _read(path: Path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def _frontmatter(text: str) -> str:
    """Return the YAML frontmatter block (between the first two `---` fences)."""
    if not text.startswith("---"):
        return ""
    parts = text.split("---", 2)
    return parts[1] if len(parts) >= 3 else ""


def _table_rows(text: str, must_have: tuple[str, ...]):
    """Yield cell-lists for a markdown table whose header contains `must_have`.

    Finds the header row (a `|`-row containing every token in `must_have`),
    skips the `| --- |` separator, and returns the data rows until the table ends.
    """
    lines = text.splitlines()
    header_idx = None
    for i, line in enumerate(lines):
        if line.lstrip().startswith("|") and all(tok.lower() in line.lower() for tok in must_have):
            header_idx = i
            break
    if header_idx is None:
        return []
    rows = []
    for line in lines[header_idx + 1:]:
        if not line.lstrip().startswith("|"):
            break
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if all(set(c) <= {"-", ":", " "} for c in cells):  # separator row
            continue
        rows.append(cells)
    return rows


def _norm(cell: str) -> str:
    """Lowercase a table cell with markdown emphasis/backticks stripped."""
    return cell.replace("`", "").replace("*", "").strip().lower()


def check_ownership_single_writer():
    text = _read(LEDGER_PROTOCOL)
    if text is None:
        return False, [f"missing {LEDGER_PROTOCOL}"]
    rows = _table_rows(text, ("path", "writer"))
    if len(rows) < 3:
        return False, ["could not parse the ownership table (expected >= 3 rows)"]

    errors = []
    # (a) no identical path claimed by two different writers.
    path_writers: dict[str, set[str]] = {}
    for cells in rows:
        if len(cells) < 2:
            continue
        path_writers.setdefault(_norm(cells[0]), set()).add(_norm(cells[1]))
    for path, writers in path_writers.items():
        if len(writers) > 1:
            errors.append(f"path '{path}' claimed by multiple writers: {sorted(writers)}")

    # (b) the frontmatter `status` field must have exactly one writer (C4/D-α).
    status_writers = {
        _norm(cells[1])
        for cells in rows
        if len(cells) >= 2 and "status field" in _norm(cells[0])
    }
    if len(status_writers) > 1:
        errors.append(
            f"frontmatter `status` claimed by {len(status_writers)} writers "
            f"{sorted(status_writers)} — C4/D-α requires exactly one"
        )
    elif len(status_writers) == 0:
        errors.append("no ownership row assigns the frontmatter `status` field")

    return (not errors), errors


def check_resources_exist():
    text = _read(SKILL_MD)
    if text is None:
        return False, [f"missing {SKILL_MD}"]
    rows = _table_rows(text, ("resource", "purpose"))
    if not rows:
        return False, ["could not find the SKILL.md Resources table"]

    errors = []
    for cells in rows:
        m = re.search(r"`([^`]+)`", cells[0])
        if not m:
            continue
        ref = m.group(1).strip()
        if "/" not in ref:  # not a path reference
            continue
        if not (SKILL_DIR / ref).exists():
            errors.append(f"Resources row points at missing file: {ref}")
    return (not errors), errors


def check_template_frontmatter():
    errors = []
    for rel, keys in REQUIRED_FRONTMATTER.items():
        text = _read(SKILL_DIR / rel)
        if text is None:
            errors.append(f"missing template: {rel}")
            continue
        fm = _frontmatter(text)
        present = {line.split(":", 1)[0].strip() for line in fm.splitlines() if ":" in line}
        for key in keys:
            if key not in present:
                errors.append(f"{rel}: frontmatter missing required key `{key}`")
    return (not errors), errors


def check_no_secrets():
    errors = []
    seen: set[Path] = set()
    self_path = Path(__file__).resolve()
    for glob in SECRET_SCAN_GLOBS:
        for path in SKILL_DIR.glob(glob):
            path = path.resolve()
            if path in seen or path == self_path:  # never scan this validator's own regexes
                continue
            seen.add(path)
            text = _read(path)
            if text is None:
                continue
            for n, line in enumerate(text.splitlines(), 1):
                if DSN_RE.search(line):
                    errors.append(f"{path.relative_to(SKILL_DIR)}:{n}: DSN with embedded credentials")
                m = SECRET_ASSIGN_RE.search(line)
                if m and not PLACEHOLDER_HINT.search(m.group(1)):
                    errors.append(
                        f"{path.relative_to(SKILL_DIR)}:{n}: secret-shaped assignment "
                        f"({m.group(1)[:12]}…)"
                    )
    return (not errors), errors


CHECKS = [
    ("ownership: one writer per status field", check_ownership_single_writer),
    ("resources: every listed file exists", check_resources_exist),
    ("templates: required frontmatter keys present", check_template_frontmatter),
    ("hygiene: no secret-shaped strings", check_no_secrets),
]


def main() -> int:
    failed = 0
    for name, fn in CHECKS:
        ok, messages = fn()
        if ok:
            print(f"PASS  {name}")
        else:
            failed += 1
            print(f"FAIL  {name}")
            for msg in messages:
                print(f"        - {msg}")
    print("-" * 48)
    print("quick_validate: OK" if not failed else f"quick_validate: {failed} check(s) FAILED")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
