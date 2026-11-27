#!/usr/bin/env python3
"""Learn allow rules from the permission prompts the operator keeps answering. No model.

  permission-suggest.py log                      # PermissionRequest hook: stdin JSON -> one log line
  permission-suggest.py suggest <dir> [--min N] [--since EPOCH] [--item-file PATH]
  permission-suggest.py apply   <dir> P<n>... | all
  permission-suggest.py decline <dir> P<n>... | all

log      Appends {ts, session, cwd, pane, tool, command} to the log. Prints nothing and
         always exits 0, so the permission dialog shows as usual.
suggest  Groups the log entries since <dir> was created into allow rules, drops dangerous
         ones, ones already allowed and ones proposed before, and keeps rules asked at least
         N times (default 3). Prints nothing when none are new. Otherwise writes a ledger
         item for `pending-watch.sh add --file` and prints its path, then one line per rule.
apply    Writes the named proposed rules (or all proposed) to their scope: "global" to the
         user settings, "project" to the list a SessionStart hook seeds into every project's
         .claude/settings.local.json. Backs up the user settings first.
decline  Marks rules declined so they are never proposed again.

Paths (env overrides, for tests): PERMISSION_LOG (~/.claude/permission-log.jsonl),
CLAUDE_USER_SETTINGS (~/.claude/settings.json), PROJECT_ALLOW_FILE
(~/.claude/project-local-allow.json). State: <dir>/permission-suggestions.json.
"""
import fnmatch
import json
import os
import re
import shlex
import shutil
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
LOG = os.environ.get("PERMISSION_LOG", os.path.join(HOME, ".claude/permission-log.jsonl"))
USER_SETTINGS = os.environ.get("CLAUDE_USER_SETTINGS", os.path.join(HOME, ".claude/settings.json"))
PROJECT_ALLOW = os.environ.get("PROJECT_ALLOW_FILE", os.path.join(HOME, ".claude/project-local-allow.json"))
LOG_MAX_BYTES = 5 * 1024 * 1024

# Never proposed: commands that delete, send data off the machine, run arbitrary code,
# change permissions or processes, or write files in ways a prefix rule cannot bound.
DENY_FIRST = {
    "rm", "rmdir", "mv", "cp", "dd", "ln", "truncate", "tee", "sudo", "su", "doas",
    "curl", "wget", "ssh", "scp", "sftp", "rsync", "nc", "ncat", "telnet", "ftp",
    "chmod", "chown", "chgrp", "kill", "pkill", "killall", "eval", "exec", "env", "xargs",
    "find", "sed", "awk", "perl", "ruby", "osascript", "open", "security", "launchctl",
    "crontab", "npx", "bunx", "pnpx", "uvx", "pipx", "psql", "mysql", "mongosh",
    "redis-cli", "sqlite3", "defaults", "diskutil", "shutdown", "reboot",
}
DENY_WORDS = {
    "push", "reset", "clean", "rebase", "restore", "rm", "delete", "remove", "merge",
    "publish", "deploy", "destroy", "prune", "kill", "login", "logout", "auth", "secret",
    "secrets", "token", "uninstall", "drop", "exec", "eval",
}
DENY_PREFIXES = (
    "herdr pane run", "herdr agent prompt", "herdr pane close", "herdr tab close",
    "herdr tab create", "herdr server", "docker run", "kubectl apply", "gh api",
    "gh pr close", "gh repo",
)
DENY_TEXT = (".env", "secret", "token", "password", "passwd", "credential", "id_rsa",
             ".pem", ".ssh", "api_key", "apikey")
DENY_MCP_WORDS = ("delete", "remove", "send", "post", "publish", "create", "update",
                  "write", "merge", "transfer", "pay", "share")
# Commands whose bare name would allow everything: only propose them with a subcommand.
NEEDS_SUBCOMMAND = {"git", "gh", "herdr", "docker", "kubectl", "npm", "pnpm", "yarn",
                    "bun", "go", "cargo", "brew", "pip", "pip3", "uv", "make", "gcloud",
                    "aws", "az"}
DEEP = {"gh", "herdr", "docker", "kubectl", "gcloud", "aws", "az"}  # take three words
INTERPRETERS = {"bash", "sh", "zsh", "python", "python3", "node"}
TEMP_DIRS = ("/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/")
PLAIN = re.compile(r"^[a-z][a-z0-9._:-]*$")
HARMLESS_REDIRECT = re.compile(r"\s*\d?>>?\s*(/dev/null|&[12])|\s*&>\s*/dev/null")
SEPARATORS = {"&&", "||", ";", "|", "&", ";;", "|&"}


def die(msg, code=2):
    print(f"permission-suggest: {msg}", file=sys.stderr)
    sys.exit(code)


# ---------- log (hook) ----------

def cmd_log():
    try:
        data = json.loads(sys.stdin.read() or "{}")
        tool = str(data.get("tool_name") or "")
        if not tool:
            return
        tin = data.get("tool_input") or {}
        command = tin.get("command") if isinstance(tin, dict) else None
        entry = {
            "ts": round(time.time(), 3),
            "session": data.get("session_id"),
            "cwd": data.get("cwd"),
            "pane": os.environ.get("HERDR_PANE_ID"),
            "tool": tool,
            "command": (command or "")[:1000] or None,
        }
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        if os.path.exists(LOG) and os.path.getsize(LOG) > LOG_MAX_BYTES:
            with open(LOG, encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
            with open(LOG, "w", encoding="utf-8") as f:
                f.writelines(lines[len(lines) // 2:])
        fd = os.open(LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass  # a logging hook must never get in the way of the dialog


# ---------- turning a prompt into a rule ----------

def segments(command):
    """Split a shell command into simple commands; None when it cannot be bounded safely."""
    text = HARMLESS_REDIRECT.sub("", command)
    if any(s in text for s in ("$(", "`", ">", "<", "\n")):
        return None
    try:
        lex = shlex.shlex(text, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        return None
    out, cur = [], []
    for t in tokens:
        if t in SEPARATORS:
            if cur:
                out.append(cur)
            cur = []
        elif set(t) <= set("();&|"):
            return None  # subshells or other syntax a prefix rule does not describe
        else:
            cur.append(t)
    if cur:
        out.append(cur)
    return out


def bash_rule(tokens):
    """(scope, rule) for one simple command, or None when it must not be proposed."""
    if not tokens or "=" in tokens[0] or tokens[0] in ("cd", "true", ":"):
        return None
    if any(d in " ".join(tokens).lower() for d in DENY_TEXT):
        return None
    first = tokens[0]
    if first in INTERPRETERS:
        if len(tokens) < 2 or tokens[1].startswith("-"):
            return None  # -c / -e run inline code
        path = tokens[1]
        if "/" not in path and not re.search(r"\.(sh|py|js|mjs|cjs)$", path):
            return None
        if path.startswith(TEMP_DIRS):
            return None
        return "project", f"Bash({first} {path}:*)"
    if "/" in first:
        if first.startswith(TEMP_DIRS):
            return None
        return "project", f"Bash({first}:*)"
    if not PLAIN.match(first) or first in DENY_FIRST:
        return None
    depth = 3 if first in DEEP else 2
    words = [first]
    for t in tokens[1:depth]:
        if not PLAIN.match(t):
            break
        words.append(t)
    if len(words) == 1 and first in NEEDS_SUBCOMMAND:
        return None
    if any(w in DENY_WORDS for w in words[1:]):
        return None
    prefix = " ".join(words)
    # Denied when the rule falls inside a denied prefix, or is broad enough to include one
    # ("herdr pane:*" would also allow "herdr pane run").
    if any(prefix == p or prefix.startswith(p + " ") or p.startswith(prefix + " ")
           for p in DENY_PREFIXES):
        return None
    return "global", f"Bash({prefix}:*)"


def rules_for(entry):
    tool = entry.get("tool") or ""
    if tool == "Bash":
        segs = segments(entry.get("command") or "")
        if not segs:
            return []
        rules = [bash_rule(s) for s in segs]
        return [r for r in rules if r]
    if tool.startswith("mcp__"):
        if any(w in tool.lower() for w in DENY_MCP_WORDS):
            return []
        return [("global", tool)]
    return []  # file edits and web access stay a decision per call


def covered(rule, allowed):
    """True when an existing allow rule already matches what `rule` would allow."""
    if rule in allowed:
        return True
    m = re.fullmatch(r"Bash\((.*):\*\)", rule)
    if not m:
        return False
    cmd = m.group(1)
    for a in allowed:
        am = re.fullmatch(r"Bash\((.*)\)", a)
        if not am:
            continue
        pat = am.group(1)
        if pat.endswith(":*"):
            p = pat[:-2]
            if cmd == p or cmd.startswith(p + " "):
                return True
        elif "*" in pat and fnmatch.fnmatchcase(cmd + " x", pat):
            return True
    return False


# ---------- state and settings files ----------

def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def write_json(path, data):
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if os.path.exists(path):
        shutil.copymode(path, tmp)
    os.replace(tmp, path)


def state_path(d):
    return os.path.join(d, "permission-suggestions.json")


def load_state(d):
    return read_json(state_path(d), {"next": 1, "rules": {}})


def allowed_now():
    settings = read_json(USER_SETTINGS, {})
    allow = list((settings.get("permissions") or {}).get("allow") or [])
    return allow + list(read_json(PROJECT_ALLOW, []))


def dir_since(d):
    st = os.stat(d)
    return getattr(st, "st_birthtime", st.st_mtime)


# ---------- commands ----------

def cmd_suggest(args):
    if not args or not os.path.isdir(args[0]):
        die("suggest needs an existing <dir>")
    d, rest = args[0], args[1:]
    minimum, since, item_file = 3, None, None
    while rest:
        flag = rest.pop(0)
        if flag in ("--min", "--since", "--item-file") and rest:
            val = rest.pop(0)
            if flag == "--min":
                minimum = int(val)
            elif flag == "--since":
                since = float(val)
            else:
                item_file = val
        else:
            die(f"unknown argument: {flag}")
    if since is None:
        since = dir_since(d)

    state = load_state(d)
    allowed = allowed_now()
    found = {}
    if os.path.exists(LOG):
        with open(LOG, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if float(e.get("ts") or 0) < since:
                    continue
                for scope, rule in set(rules_for(e)):
                    r = found.setdefault(rule, {"scope": scope, "count": 0, "panes": set(),
                                                "example": None})
                    r["count"] += 1
                    if e.get("pane"):
                        r["panes"].add(e["pane"])
                    if not r["example"]:
                        r["example"] = (e.get("command") or e.get("tool") or "")[:80]

    new = [(rule, r) for rule, r in sorted(found.items(), key=lambda kv: -kv[1]["count"])
           if r["count"] >= minimum and rule not in state["rules"] and not covered(rule, allowed)]
    if not new:
        return

    lines = []
    for rule, r in new:
        pid = f"P{state['next']}"
        state["next"] += 1
        state["rules"][rule] = {"id": pid, "scope": r["scope"], "status": "proposed",
                                "count": r["count"], "proposed": time.strftime("%Y-%m-%d %H:%M")}
        panes = ", ".join(sorted(r["panes"])) or "-"
        lines.append(f"- {pid} ({r['scope']}): {rule} — {r['count']} lần, pane {panes} — vd: {r['example']}")

    if not item_file:
        os.makedirs(os.path.join(d, "questions"), exist_ok=True)
        item_file = os.path.join(d, "questions", f"permissions-{time.strftime('%Y%m%d-%H%M%S')}.txt")
    with open(item_file, "w", encoding="utf-8") as f:
        f.write("permissions\n")
        f.write("Câu hỏi: Cho phép sẵn các lệnh bạn đã phải duyệt nhiều lần? "
                "Trả lời các P<n> đồng ý (vd \"P1 P3\"), \"tất cả\" hoặc \"không\"; "
                "mục không chọn sẽ không được đề xuất lại.\n")
        f.write("\n".join(lines) + "\n")
        f.write("Chặn: không chặn việc nào; quy tắc có hiệu lực cho session mở sau khi áp dụng\n")
    write_json(state_path(d), state)
    print(item_file)
    print("\n".join(lines))


def pick(state, ids):
    proposed = {v["id"]: k for k, v in state["rules"].items() if v["status"] == "proposed"}
    if ids == ["all"]:
        return list(proposed.values())
    unknown = [i for i in ids if i not in proposed]
    if unknown:
        die(f"not a proposed rule: {' '.join(unknown)} (proposed: {' '.join(sorted(proposed)) or 'none'})")
    return [proposed[i] for i in ids]


def cmd_apply(args):
    if len(args) < 2:
        die("apply needs <dir> and P<n>... or all")
    d = args[0]
    state = load_state(d)
    rules = pick(state, args[1:])
    if not rules:
        return
    glob = [r for r in rules if state["rules"][r]["scope"] == "global"]
    proj = [r for r in rules if state["rules"][r]["scope"] == "project"]
    if glob:
        settings = read_json(USER_SETTINGS, {})
        if os.path.exists(USER_SETTINGS):
            shutil.copy2(USER_SETTINGS, f"{USER_SETTINGS}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
        allow = settings.setdefault("permissions", {}).setdefault("allow", [])
        allow.extend(r for r in glob if r not in allow)
        write_json(USER_SETTINGS, settings)
    if proj:
        lst = read_json(PROJECT_ALLOW, [])
        lst.extend(r for r in proj if r not in lst)
        write_json(PROJECT_ALLOW, lst)
    for r in rules:
        state["rules"][r]["status"] = "applied"
        target = USER_SETTINGS if r in glob else PROJECT_ALLOW
        print(f"applied {state['rules'][r]['id']} {r} -> {target}")
    write_json(state_path(d), state)


def cmd_decline(args):
    if len(args) < 2:
        die("decline needs <dir> and P<n>... or all")
    d = args[0]
    state = load_state(d)
    for r in pick(state, args[1:]):
        state["rules"][r]["status"] = "declined"
        print(f"declined {state['rules'][r]['id']} {r}")
    write_json(state_path(d), state)


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip())
        sys.exit(2)
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "log":
        cmd_log()
    elif cmd == "suggest":
        cmd_suggest(args)
    elif cmd == "apply":
        cmd_apply(args)
    elif cmd == "decline":
        cmd_decline(args)
    else:
        die(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
