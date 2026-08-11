#!/usr/bin/env python3
"""Optional active barrier poll-and-wake driver for `--discussion` (head-chief).

Generalizes the improvised watch-peers.py from the 2026-08-11 reference run (report Addendum).

WHY THIS EXISTS
    Across a `--discussion` round barrier, NOTHING auto-advances: the chief must release the next
    round, and between rounds every peer is idle waiting on the chief. A purely reactive chief that
    parks itself on an inbound "round done" ping can stall forever, because those pings may be held
    for the user's approval and never delivered (live evidence, report Part II). Detecting a dead
    *peer* (C1) does not help when the stalled party is the chief itself — silent *idle*, the twin of
    silent *death*.

WHAT IT DOES
    Polls `herdr agent list` and, the moment NO panel peer is still `working`, prints a `WAKE:` line
    (the ball is back in the chief's court) and exits so the chief can drive the next barrier. A
    bounded `--timeout` guarantees a wedged peer still surfaces (C13) instead of hanging the run.

WHERE IT SITS
    The active-driver DUTY is persona-encoded in the chief (Decision A) — that is the guarantee. This
    script is an OPTIONAL convenience for operators who want automatic wake; the mode is fully usable
    without it. See references/discussion-mode.md §F.4.

HERDR OUTPUT CONTRACT (adjust the two constants below if your herdr build differs)
    - Preferred: `herdr agent list --json` → JSON. Accepts a top-level list, or a dict wrapping the
      list under one of AGENTS_KEYS. Each entry is a dict; the agent's name is read from the first
      present of NAME_KEYS and its state from the first present of STATE_KEYS.
    - Fallback: if `--json` is unsupported or unparseable, the bare `herdr agent list` text is scanned
      line-by-line; a peer counts as working when its line contains the working-state token as a word.
    A peer is "working" iff its state token (lower-cased) is in WORKING_STATES (default {"working"};
    override with --working-state).

USAGE
    watch-peers.py --peers maestro,sentinel,concierge [--self mds-head-chief]
    watch-peers.py --prefix mds- --self mds-head-chief          # panel = mds-* minus the chief
    watch-peers.py --peers a,b,c --once                         # single poll (persona-encoded check)
    watch-peers.py --peers a,b,c --interval 15 --timeout 900 --wake-cmd 'echo advance'

EXIT CODES
    0  no panel peer is working — the chief's turn (or --wake-cmd ran); the driver's success case
    2  --timeout elapsed with a peer still working (wedged peer → surface via reconcile, F.6)
    3  herdr unavailable / output unparseable — fall back to persona-encoded polling
    4  bad arguments
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import time

# --- herdr output contract (see module docstring) ---------------------------------------------
HERDR_CMD = ["herdr", "agent", "list"]
AGENTS_KEYS = ("agents", "panes", "sessions", "items")  # dict wrappers to unwrap in JSON mode
NAME_KEYS = ("name", "s_name", "session", "title", "pane")  # where an agent's name may live
STATE_KEYS = ("state", "status", "activity")  # where an agent's activity token may live
DEFAULT_WORKING_STATES = {"working"}


def _run_herdr(json_mode: bool) -> "tuple[int, str]":
    """Invoke herdr; return (returncode, stdout). Never raises on non-zero exit."""
    cmd = HERDR_CMD + (["--json"] if json_mode else [])
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return 127, ""
    return proc.returncode, proc.stdout or ""


def _working_names_from_json(raw: str, working_states: "set[str]") -> "set[str] | None":
    """Parse JSON herdr output → set of names whose state is a working state. None = not JSON."""
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return None
    # Unwrap a dict that carries the list under a known key (herdr builds vary).
    if isinstance(data, dict):
        data = next((data[k] for k in AGENTS_KEYS if isinstance(data.get(k), list)), None)
    if not isinstance(data, list):
        return None
    working = set()
    for entry in data:
        if not isinstance(entry, dict):
            continue
        name = next((str(entry[k]) for k in NAME_KEYS if entry.get(k)), None)
        state = next((str(entry[k]) for k in STATE_KEYS if entry.get(k)), "")
        if name and state.strip().lower() in working_states:
            working.add(name)
    return working


def _working_names_from_text(raw: str, peers: "list[str]", working_states: "set[str]") -> "set[str]":
    """Fallback text scan: a peer is working if its line carries a working token as a whole word."""
    token_re = re.compile(r"\b(" + "|".join(re.escape(s) for s in working_states) + r")\b", re.I)
    working = set()
    for line in raw.splitlines():
        for peer in peers:
            # Match the peer name as a word so a substring name can't false-positive on another row.
            if re.search(r"\b" + re.escape(peer) + r"\b", line) and token_re.search(line):
                working.add(peer)
    return working


def poll_working(peers: "list[str]", working_states: "set[str]") -> "set[str] | None":
    """One poll. Return the subset of `peers` currently working, or None if herdr is unusable.

    `peers` empty → treat every agent herdr reports as a panel member (minus --self, applied by the
    caller before this function). JSON is tried first; text is the fallback.
    """
    rc, out = _run_herdr(json_mode=True)
    if rc == 127:
        return None
    parsed = _working_names_from_json(out, working_states)
    if parsed is None:
        # herdr didn't understand --json (or emitted text); retry bare and scan text.
        rc, out = _run_herdr(json_mode=False)
        if rc == 127 or not out.strip():
            return None
        if not peers:
            # Text mode needs explicit peer names to attribute a state to a row.
            return None
        return _working_names_from_text(out, peers, working_states)
    # JSON mode: restrict to the declared panel when one was given.
    return {n for n in parsed if n in peers} if peers else parsed


def main() -> int:
    p = argparse.ArgumentParser(
        description="Wake the chief when no --discussion panel peer is still `working`.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    src = p.add_mutually_exclusive_group()
    src.add_argument("--peers", default="", help="comma-separated panel session/vibe names")
    src.add_argument("--prefix", default="", help="treat herdr agents whose name starts with this as the panel")
    p.add_argument("--self", dest="self_name", default="", help="the chief's own name, always excluded")
    p.add_argument("--working-state", action="append", default=[],
                   help="state token(s) that count as working (repeatable; default: working)")
    p.add_argument("--interval", type=float, default=15.0, help="seconds between polls (default 15)")
    p.add_argument("--timeout", type=float, default=900.0, help="max seconds to watch (default 900)")
    p.add_argument("--once", action="store_true", help="poll once and exit (no loop)")
    p.add_argument("--wake-cmd", default="", help="shell command to run on wake (optional)")
    args = p.parse_args()

    if not shutil.which(HERDR_CMD[0]):
        print(f"herdr-unavailable: `{HERDR_CMD[0]}` not on PATH — fall back to persona-encoded polling",
              file=sys.stderr)
        return 3

    peers = [x.strip() for x in args.peers.split(",") if x.strip()]
    working_states = {s.strip().lower() for s in args.working_state} or set(DEFAULT_WORKING_STATES)
    if args.interval <= 0 or args.timeout <= 0:
        print("bad-args: --interval and --timeout must be positive", file=sys.stderr)
        return 4

    deadline = time.monotonic() + args.timeout
    while True:
        working = poll_working(peers, working_states)
        if args.prefix:  # narrow to the panel prefix when polling all agents
            working = None if working is None else {n for n in working if n.startswith(args.prefix)}
        if working is not None and args.self_name:
            working.discard(args.self_name)

        if working is None:
            print("herdr-unparseable: could not read agent states — fall back to persona-encoded polling",
                  file=sys.stderr)
            return 3
        if not working:
            # The ball is back in the chief's court: no peer is working the current round.
            print("WAKE: no panel peer is working — chief's turn to drive the next barrier")
            if args.wake_cmd:
                subprocess.run(args.wake_cmd, shell=True)
            return 0

        if args.once or time.monotonic() >= deadline:
            if args.once:
                print(f"still-working: {sorted(working)}")
                return 2
            print(f"TIMEOUT: peers still working after {args.timeout:.0f}s: {sorted(working)} — "
                  "surface as a possibly-wedged peer (reconcile, F.6)", file=sys.stderr)
            return 2
        time.sleep(min(args.interval, max(0.0, deadline - time.monotonic())))


if __name__ == "__main__":
    sys.exit(main())
