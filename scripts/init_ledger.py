#!/usr/bin/env python3
"""Idempotent bootstrap for the head-chief ledger (.orchestrator/).

Creates the ledger skeleton at the project root and seeds the chief system
prompt from the skill's assets. Never overwrites existing files, so it is
safe to run on every /head-chief trigger.

Also the single source of truth for ledger timestamps (C7): `--now` prints one
canonical ISO-8601 UTC stamp so no chief ever hand-types a date.

Usage:
    init_ledger.py --project-root <path>   # bootstrap (or re-check) the ledger
    init_ledger.py --now                   # print canonical UTC stamp (frontmatter)
    init_ledger.py --now --filename        # print filesystem-safe filename variant
    init_ledger.py --test                  # run self-test in a temp dir

Exit codes: 0 = ok, 1 = error.
"""

import argparse
import re
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
LEDGER_DIRNAME = ".orchestrator"
SYSTEM_PROMPT_ASSET = SKILL_DIR / "assets" / "chief-system-prompt.md"

# C7 canonical stamp: ISO-8601 UTC with a literal Z (unambiguous zone, sortable).
# Frontmatter/body form -> 2026-08-11T06:28:00Z ; filename form -> 20260811-0628Z.
STAMP_FMT = "%Y-%m-%dT%H:%M:%SZ"
FILENAME_FMT = "%Y%m%d-%H%MZ"
STAMP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
FILENAME_RE = re.compile(r"^\d{8}-\d{4}Z$")


def now_stamp(filename: bool = False) -> str:
    """Return the canonical UTC timestamp; filename=True gives the compact variant.

    The only sanctioned stamp source for the ledger — never hand-type a date.
    """
    dt = datetime.now(timezone.utc)
    return dt.strftime(FILENAME_FMT if filename else STAMP_FMT)


def init_ledger(project_root: Path) -> list[str]:
    """Create the ledger skeleton; return human-readable actions taken."""
    if not project_root.is_dir():
        raise SystemExit(f"error: project root does not exist: {project_root}")

    ledger = project_root / LEDGER_DIRNAME
    actions = []

    for sub in (ledger, ledger / "tracks", ledger / "logs"):
        if not sub.exists():
            sub.mkdir(parents=True)
            actions.append(f"created {sub.relative_to(project_root)}/")

    system_prompt = ledger / "system-prompt.md"
    if not system_prompt.exists():
        if not SYSTEM_PROMPT_ASSET.exists():
            raise SystemExit(f"error: missing skill asset: {SYSTEM_PROMPT_ASSET}")
        shutil.copyfile(SYSTEM_PROMPT_ASSET, system_prompt)
        actions.append(f"seeded {system_prompt.relative_to(project_root)} from skill asset")

    return actions


def self_test() -> None:
    """Bootstrap twice in a temp dir; assert idempotency and no overwrites."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)

        first = init_ledger(root)
        assert (root / LEDGER_DIRNAME / "tracks").is_dir()
        assert (root / LEDGER_DIRNAME / "logs").is_dir()
        prompt = root / LEDGER_DIRNAME / "system-prompt.md"
        assert prompt.is_file() and prompt.stat().st_size > 0
        assert len(first) == 4, first

        # Second run must be a no-op and must not clobber user edits.
        prompt.write_text("user-customized", encoding="utf-8")
        second = init_ledger(root)
        assert second == [], second
        assert prompt.read_text(encoding="utf-8") == "user-customized"

    # C7 stamp helper: exact format + monotonic sanity (ISO sorts lexically).
    stamp = now_stamp()
    assert STAMP_RE.match(stamp), f"bad --now stamp: {stamp}"
    fname = now_stamp(filename=True)
    assert FILENAME_RE.match(fname), f"bad --now --filename stamp: {fname}"
    assert now_stamp() >= stamp, "stamps must be monotonic non-decreasing"

    print("self-test: OK")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, help="project root directory")
    parser.add_argument("--now", action="store_true", help="print canonical UTC stamp and exit")
    parser.add_argument(
        "--filename",
        action="store_true",
        help="with --now: print the filesystem-safe filename variant",
    )
    parser.add_argument("--test", action="store_true", help="run self-test")
    args = parser.parse_args()

    if args.test:
        self_test()
        return
    if args.now:
        # No side effects — pure stamp source for filenames + frontmatter.
        print(now_stamp(filename=args.filename))
        return
    if not args.project_root:
        parser.error("--project-root is required (or use --now / --test)")

    actions = init_ledger(args.project_root.resolve())
    if actions:
        print("\n".join(actions))
    else:
        print(f"ledger already initialized at {args.project_root.resolve() / LEDGER_DIRNAME}")


if __name__ == "__main__":
    main()
