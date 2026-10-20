#!/usr/bin/env python3
"""find-implementer.py — which Claude Code session implemented each PR.

Usage: find-implementer.py OWNER/REPO#N [OWNER/REPO#N ...]

For each PR (via `gh pr view`) it scans Claude Code transcripts under
~/.claude/projects for evidence that a session pushed the PR's head branch:
  - a `git push` result whose ref line targets the branch ("... -> BRANCH")
    and names the repo, or
  - a `pr-link` record for the PR URL (written when a session opens the PR).
Subagent transcripts count for their parent session. The session with the
latest evidence is the "latest implementer". Reviewers only read PRs, so they
never match.

Prints JSON: {"self": {...}|null, "prs": [{repo, number, url, branch, head,
commits, implementer: {session_id, name, cwd, last_evidence, evidence,
live: {pid, name, status, socket}|null}|null}]}
"""
import glob
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
PROJECTS = os.path.join(HOME, ".claude", "projects")
SESSIONS = os.path.join(HOME, ".claude", "sessions")


def pr_info(ref):
    m = re.fullmatch(r"([\w.-]+)/([\w.-]+)#(\d+)", ref)
    if not m:
        sys.exit(f"bad PR ref {ref!r}; expected OWNER/REPO#N")
    owner, repo, num = m.groups()
    out = subprocess.run(
        ["gh", "pr", "view", num, "-R", f"{owner}/{repo}", "--json",
         "url,headRefName,headRefOid,commits"],
        capture_output=True, text=True, check=True).stdout
    d = json.loads(out)
    return {"repo": f"{owner}/{repo}", "number": int(num), "url": d["url"],
            "branch": d["headRefName"], "head": d["headRefOid"][:7],
            "commits": len(d["commits"])}


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False
    except OSError:
        return False


def live_sessions():
    out = {}
    for path in glob.glob(os.path.join(SESSIONS, "*.json")):
        try:
            s = json.load(open(path))
        except (OSError, ValueError):
            continue
        if s.get("sessionId") and alive(int(s.get("pid", 0))):
            out[s["sessionId"]] = s
    return out


def self_session(live):
    """The session whose claude process is an ancestor of this script."""
    by_pid = {int(s["pid"]): s for s in live.values()}
    pid = os.getppid()
    while pid > 1:
        if pid in by_pid:
            return by_pid[pid]
        r = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                           capture_output=True, text=True)
        try:
            pid = int(r.stdout.strip())
        except ValueError:
            return None
    return None


PUSH_CMD = re.compile(r"\bgit\b[^|;&]*\bpush\b|squash\.sh\b.*\bpush\b")


def texts(o, push_ids):
    """pr-link records, and results of push commands, in one transcript line.

    Only results of a Bash call that itself ran `git push` count, so a session
    that merely printed someone else's push output (grep, cat) never matches.
    """
    if o.get("type") == "pr-link":
        yield "pr-link", o.get("prUrl", "")
    c = (o.get("message") or {}).get("content")
    if not isinstance(c, list):
        return
    for b in c:
        if b.get("type") == "tool_use" and b.get("name") == "Bash" and \
                PUSH_CMD.search((b.get("input") or {}).get("command", "")):
            push_ids.add(b.get("id"))
        elif b.get("type") == "tool_result" and b.get("tool_use_id") in push_ids:
            t = b.get("content")
            yield "push", t if isinstance(t, str) else json.dumps(t)


def scan(prs):
    # pr index -> (rank, ts, session_id, cwd, evidence); a push outranks a
    # pr-link, and within a rank the latest wins.
    best = {}
    needles = {p["branch"] for p in prs} | {p["url"] for p in prs} | {"push"}
    files = glob.glob(os.path.join(PROJECTS, "*", "*.jsonl")) + \
        glob.glob(os.path.join(PROJECTS, "*", "*", "subagents", "*.jsonl"))
    for path in files:
        try:
            raw = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if not any(n in raw for n in needles):
            continue
        if not any(p["branch"] in raw or p["url"] in raw for p in prs):
            continue
        parts = path.split(os.sep)
        sid = parts[-3] if parts[-2] == "subagents" else parts[-1][:-6]
        push_ids, cwd = set(), ""
        # The start cwd decides where `claude --resume` can find the session.
        m = re.search(r'"cwd":"([^"]+)"', raw)
        if m:
            cwd = m.group(1)
        for line in raw.splitlines():
            if not any(n in line for n in needles):
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            ts = o.get("timestamp", "")
            for kind, t in texts(o, push_ids):
                for i, p in enumerate(prs):
                    repo = p["repo"].split("/")[1].lower()
                    hit = None
                    if kind == "pr-link" and t.rstrip("/") == p["url"].rstrip("/"):
                        hit = "opened PR"
                    elif kind == "push" and repo in t.lower() and re.search(
                            r"->\s+" + re.escape(p["branch"]) + r"(?![\w/.-])", t):
                        hit = "pushed branch"
                    rank = 2 if hit == "pushed branch" else 1
                    if hit and (rank, ts) >= best.get(i, (0, ""))[:2]:
                        best[i] = (rank, ts, sid, cwd, hit)
    return best


def title(sid):
    for path in glob.glob(os.path.join(PROJECTS, "*", sid, "custom-title.json")):
        try:
            return json.load(open(path)).get("customTitle")
        except (OSError, ValueError):
            pass
    return None


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    prs = [pr_info(r) for r in sys.argv[1:]]
    live = live_sessions()
    me = self_session(live)
    best = scan(prs)
    for i, p in enumerate(prs):
        if i not in best:
            p["implementer"] = None
            continue
        _, ts, sid, cwd, ev = best[i]
        s = live.get(sid)
        p["implementer"] = {
            "session_id": sid, "name": (s or {}).get("name") or title(sid),
            "cwd": cwd, "last_evidence": ts, "evidence": ev,
            "live": {"pid": s["pid"], "name": s.get("name"),
                     "status": s.get("status"),
                     "socket": s.get("messagingSocketPath")} if s else None,
        }
    print(json.dumps({
        "self": {"session_id": me["sessionId"], "name": me.get("name")} if me else None,
        "prs": prs}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
