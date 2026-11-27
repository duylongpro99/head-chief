#!/usr/bin/env python3
"""Learn allow rules from the permission prompts the operator keeps answering. No model.

  permission-suggest.py log                      # PermissionRequest hook: stdin JSON -> one log line
  permission-suggest.py seed                     # SessionStart hook: project rules -> this project
  permission-suggest.py suggest <dir> [--min N] [--since EPOCH]
  permission-suggest.py apply   <dir> P<n>... | D<n> | all
  permission-suggest.py decline <dir> P<n>... | D<n> | all

log      Appends {ts, session, cwd, pane, tool, command} to the log (mode 600). Prints
         nothing and always exits 0, so the permission dialog shows as usual.
seed     Merges the project rule list into $CLAUDE_PROJECT_DIR/.claude/settings.local.json
         when that directory is a git work tree root. Always exits 0.
suggest  Turns the log entries since the supervision started into allow rules. Only known
         read-only shapes are proposed (an allowlist), plus absolute paths of existing
         project scripts. Rules already allowed, denied, or proposed before are skipped;
         a rule needs N prompts (default 3). Prints nothing when none are new. Otherwise
         adds one ledger item through pending-watch.sh, then prints the D<n> and one line
         per rule. Rules count as proposed only once that add succeeded.
apply    Writes rules to their scope: "global" to the user settings (backed up first),
         "project" to the list `seed` copies into each project. D<n> or all = every rule
         of that item (or every item) that is still proposed.
decline  Marks rules declined so they are never proposed again.

Paths (env overrides, for tests): PERMISSION_LOG (~/.claude/permission-log.jsonl),
CLAUDE_USER_SETTINGS (~/.claude/settings.json), PROJECT_ALLOW_FILE
(~/.claude/project-local-allow.json), PENDING_WATCH (pending-watch.sh next to this file).
State: <dir>/permission-suggestions.json.
"""
import fnmatch
import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
HERE = os.path.dirname(os.path.realpath(__file__))
LOG = os.environ.get("PERMISSION_LOG", os.path.join(HOME, ".claude/permission-log.jsonl"))
USER_SETTINGS = os.environ.get("CLAUDE_USER_SETTINGS", os.path.join(HOME, ".claude/settings.json"))
PROJECT_ALLOW = os.environ.get("PROJECT_ALLOW_FILE", os.path.join(HOME, ".claude/project-local-allow.json"))
PENDING_WATCH = os.environ.get("PENDING_WATCH", os.path.join(HERE, "pending-watch.sh"))
LOG_MAX_BYTES = 5 * 1024 * 1024
KEEP_BACKUPS = 3

# Allowlist. A global rule is proposed only when it has one of these shapes.
# 1. A command that only reads, used without a subcommand: "Bash(<cmd>:*)".
SAFE_SINGLE = {
    "ls", "cat", "head", "tail", "wc", "grep", "rg", "fd", "tree", "jq", "yq", "stat",
    "file", "du", "df", "diff", "which", "pwd", "date", "sort", "uniq", "cut", "tr",
    "basename", "dirname", "realpath", "readlink", "ps", "lsof", "pgrep", "uname",
    "whoami", "hostname", "cmp", "md5", "shasum", "sha256sum", "column", "nl",
}
# 2. A tool with subcommands, where one subcommand word is a read verb and none is a
#    risky one: "Bash(<tool> <sub> [<sub>]:*)". build/test/vet/check run the project's
#    own code, which is what workers are there to do.
SAFE_VERBS = {
    "status", "log", "diff", "show", "list", "ls", "get", "view", "describe", "read",
    "current", "wait", "version", "help", "info", "inspect", "search", "test", "build",
    "vet", "check", "lint", "outdated", "doctor", "logs", "blame", "shortlog", "whoami",
    "rev-parse", "explain", "top", "ps", "events", "history", "tree",
}
SAFE_VERB_PREFIXES = ("describe-", "list-", "get-", "show-")
RISKY_WORDS = {
    "push", "reset", "clean", "rebase", "restore", "rm", "delete", "remove", "merge",
    "publish", "deploy", "destroy", "prune", "kill", "login", "logout", "auth", "secret",
    "secrets", "token", "uninstall", "drop", "exec", "eval", "run", "dlx", "x", "create",
    "cp", "mv", "sync", "apply", "scale", "terminate", "stop", "close", "prompt", "send",
    "checkout", "switch", "stash", "branch", "tag", "commit", "config", "set", "edit",
    "update", "upgrade", "install", "add", "start", "restart", "patch", "replace", "write",
}
DEEP = {"gh", "herdr", "docker", "kubectl", "gcloud", "aws", "az"}  # up to three words
# 3. An MCP tool whose action is a read: "mcp__<server>__<action>".
MCP_READ = re.compile(r"^(get|list|read|search|find|describe|view|show)(_|$)")

SECRET_TEXT = (".env", "secret", "token", "password", "passwd", "credential", "id_rsa",
               ".pem", ".ssh", "api_key", "apikey")
INTERPRETERS = {"bash", "sh", "zsh", "python", "python3", "node"}
# Names that are commands, not project scripts, wherever they are installed.
KNOWN_COMMANDS = SAFE_SINGLE | INTERPRETERS | {
    "python", "rm", "rmdir", "mv", "cp", "dd", "ln", "curl", "wget", "ssh", "scp", "rsync",
    "nc", "sudo", "chmod", "chown", "kill", "pkill", "killall", "env", "xargs", "find",
    "sed", "awk", "perl", "ruby", "php", "lua", "fish", "deno", "bun", "npx", "osascript",
    "open", "timeout", "nohup", "git", "gh", "docker", "kubectl", "aws", "gcloud", "npm",
    "pnpm", "yarn", "uv", "pip", "tee", "truncate", "eval", "exec",
}
SCRIPT_EXT = re.compile(r"\.(sh|bash|zsh|py|js|mjs|cjs)$")
# World-writable places: a rule for a script there would allow whatever lands there next.
TEMP_DIRS = tuple(os.environ.get("PERMISSION_SUGGEST_TEMP_DIRS",
                                 "/tmp/:/private/tmp/:/var/folders/:/private/var/folders/").split(":"))
SYSTEM_DIRS = ("/bin/", "/sbin/", "/usr/", "/opt/homebrew/", "/opt/local/", "/nix/",
               "/System/", "/Library/", "/Applications/")
PLAIN = re.compile(r"^[a-z][a-z0-9._-]*$")
HARMLESS_REDIRECT = re.compile(r"\s*\d?>>?\s*(/dev/null|&[12])|\s*&>\s*/dev/null")
SEPARATORS = {"&&", "||", ";", "|", "&", ";;", "|&"}


def die(msg, code=2):
    print(f"permission-suggest: {msg}", file=sys.stderr)
    sys.exit(code)


# ---------- hooks ----------

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


def cmd_seed():
    try:
        sys.stdin.read()
        rules = read_json(PROJECT_ALLOW, [])
        d = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
        if not rules or os.path.realpath(d) in (os.path.realpath(HOME), "/"):
            return
        top = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True)
        if top.returncode or os.path.realpath(top.stdout.strip()) != os.path.realpath(d):
            return
        target = os.path.join(d, ".claude", "settings.local.json")
        settings = read_json(target, {})
        allow = settings.setdefault("permissions", {}).setdefault("allow", [])
        missing = [r for r in rules if r not in allow]
        if missing:
            allow.extend(missing)
            write_json(target, settings)
        ignored = subprocess.run(["git", "-C", d, "check-ignore", "-q", ".claude/settings.local.json"])
        if ignored.returncode != 0:
            ex = subprocess.run(["git", "-C", d, "rev-parse", "--git-path", "info/exclude"],
                                capture_output=True, text=True).stdout.strip()
            if ex:
                ex = ex if os.path.isabs(ex) else os.path.join(d, ex)
                os.makedirs(os.path.dirname(ex), exist_ok=True)
                with open(ex, "a", encoding="utf-8") as f:
                    f.write(".claude/settings.local.json\n")
    except Exception:
        pass  # never block a session from starting


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


def script_path(path, cwd):
    """Absolute path of an existing project script, or None."""
    if not cwd and not os.path.isabs(path):
        return None
    full = os.path.normpath(path if os.path.isabs(path) else os.path.join(cwd, path))
    if full.startswith(TEMP_DIRS + SYSTEM_DIRS) or not os.path.isfile(full):
        return None
    return full


def bash_rule(tokens, cwd):
    """(scope, rule) for one simple command, or None when it is not a known safe shape."""
    if not tokens or "=" in tokens[0] or tokens[0] in ("cd", "true", ":"):
        return None
    if any(s in " ".join(tokens).lower() for s in SECRET_TEXT):
        return None
    first = tokens[0]
    if first in INTERPRETERS:
        # "<interpreter> <script>" only; -c / -e and the like run inline code.
        if len(tokens) < 2 or tokens[1].startswith("-") or not SCRIPT_EXT.search(tokens[1]):
            return None
        full = script_path(tokens[1], cwd)
        return ("project", f"Bash({first} {full}:*)") if full else None
    if "/" in first:
        if re.sub(r"[0-9.]+$", "", os.path.basename(first)) in KNOWN_COMMANDS:
            return None  # /bin/rm, ~/.local/bin/python3.11: a command, not a project script
        full = script_path(first, cwd)
        return ("project", f"Bash({full}:*)") if full else None
    if not PLAIN.match(first):
        return None
    words = [first]
    for t in tokens[1:3 if first in DEEP else 2]:
        if not PLAIN.match(t):
            break
        words.append(t)
    subs = words[1:]
    if not subs:
        return ("global", f"Bash({first}:*)") if first in SAFE_SINGLE else None
    if first in SAFE_SINGLE:
        return ("global", f"Bash({first}:*)")  # "ls build": the bare command is the rule
    if any(w in RISKY_WORDS for w in subs):
        return None
    if not any(w in SAFE_VERBS or w.startswith(SAFE_VERB_PREFIXES) for w in subs):
        return None
    return "global", f"Bash({' '.join(words)}:*)"


def rules_for(entry):
    tool = entry.get("tool") or ""
    if tool == "Bash":
        segs = segments(entry.get("command") or "")
        if not segs:
            return []
        return [r for r in (bash_rule(s, entry.get("cwd")) for s in segs) if r]
    if tool.startswith("mcp__") and MCP_READ.match(tool.rsplit("__", 1)[-1]):
        return [("global", tool)]
    return []  # file edits, web access and writing tools stay a decision per call


def matches(rule, patterns):
    """True when one of `patterns` (allow or deny rules) already covers `rule`."""
    if rule in patterns:
        return True
    m = re.fullmatch(r"Bash\((.*):\*\)", rule)
    if not m:
        return False
    cmd = m.group(1)
    for a in patterns:
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


# ---------- files ----------

def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def write_json(path, data):
    path = os.path.realpath(path)  # keep a symlinked settings file a symlink
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if os.path.exists(path):
        shutil.copymode(path, tmp)
    os.replace(tmp, path)


def backup_settings():
    real = os.path.realpath(USER_SETTINGS)
    if not os.path.exists(real):
        return
    shutil.copy2(real, f"{real}.bak-permission-suggest-{time.strftime('%Y%m%d-%H%M%S')}")
    for old in sorted(glob.glob(f"{real}.bak-permission-suggest-*"))[:-KEEP_BACKUPS]:
        os.remove(old)


def settings_rules(path, key):
    s = read_json(path, {})
    return list(((s.get("permissions") or {}) if isinstance(s, dict) else {}).get(key) or [])


def state_path(d):
    return os.path.join(d, "permission-suggestions.json")


def load_state(d):
    return read_json(state_path(d), {"next": 1, "rules": {}})


def start_time(d):
    """When the supervision started: birth time of <dir>, else its oldest file's mtime."""
    st = os.stat(d)
    if hasattr(st, "st_birthtime"):
        return st.st_birthtime
    times = [os.stat(os.path.join(r, f)).st_mtime for r, _, fs in os.walk(d) for f in fs]
    return min(times + [st.st_mtime])


# ---------- commands ----------

def read_log(since):
    if not os.path.exists(LOG):
        return
    with open(LOG, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                e = json.loads(line)
                if isinstance(e, dict) and float(e.get("ts") or 0) >= since:
                    yield e
            except (ValueError, TypeError):
                continue


def cmd_suggest(args):
    if not args or not os.path.isdir(args[0]):
        die("suggest needs an existing <dir>")
    d, rest = args[0], args[1:]
    minimum, since = 3, None
    while rest:
        flag = rest.pop(0)
        if flag in ("--min", "--since") and rest:
            val = rest.pop(0)
            minimum, since = (int(val), since) if flag == "--min" else (minimum, float(val))
        else:
            die(f"unknown argument: {flag}")
    state = load_state(d)
    if since is None:
        since = state.setdefault("since", start_time(d))

    found = {}
    for e in read_log(since):
        for scope, rule in set(rules_for(e)):
            r = found.setdefault(rule, {"scope": scope, "count": 0, "panes": set(),
                                        "cwds": set(), "example": None})
            r["count"] += 1
            if e.get("pane"):
                r["panes"].add(e["pane"])
            if e.get("cwd"):
                r["cwds"].add(e["cwd"])
            if not r["example"]:
                r["example"] = (e.get("command") or e.get("tool") or "")[:80]

    allowed = settings_rules(USER_SETTINGS, "allow") + list(read_json(PROJECT_ALLOW, []))
    denied = settings_rules(USER_SETTINGS, "deny")
    for cwd in {c for r in found.values() for c in r["cwds"]}:
        for name in ("settings.json", "settings.local.json"):
            denied += settings_rules(os.path.join(cwd, ".claude", name), "deny")

    new = [(rule, r) for rule, r in sorted(found.items(), key=lambda kv: (-kv[1]["count"], kv[0]))
           if r["count"] >= minimum and rule not in state["rules"]
           and not matches(rule, allowed) and not matches(rule, denied)]
    if not new:
        if "since" not in read_json(state_path(d), {}):
            write_json(state_path(d), state)
        return

    lines, ids = [], []
    for i, (rule, r) in enumerate(new):
        pid = f"P{state['next'] + i}"
        ids.append(pid)
        panes = ", ".join(sorted(r["panes"])) or "-"
        lines.append(f"- {pid} ({r['scope']}): {rule} — {r['count']} lần, pane {panes} — vd: {r['example']}")
    os.makedirs(os.path.join(d, "questions"), exist_ok=True)
    item = os.path.join(d, "questions", f"permissions-{time.strftime('%Y%m%d-%H%M%S')}.txt")
    with open(item, "w", encoding="utf-8") as f:
        f.write("permissions\n")
        f.write("Câu hỏi: Cho phép sẵn các lệnh bạn đã phải duyệt nhiều lần? Xem từng dòng: "
                "global áp dụng cho mọi project. Trả lời các P<n> đồng ý (vd \"P1 P3\"), "
                "\"tất cả\" hoặc \"không\"; mục không chọn sẽ không được đề xuất lại.\n")
        f.write("\n".join(lines) + "\n")
        f.write("Chặn: không chặn việc nào; quy tắc có hiệu lực cho session mở sau khi áp dụng\n")

    add = subprocess.run(["bash", PENDING_WATCH, "add", d, "--file", item],
                         capture_output=True, text=True)
    sys.stderr.write(add.stderr)
    did = next((l for l in add.stdout.split() if re.fullmatch(r"D\d+", l)), None)
    if add.returncode or not did:
        die(f"pending-watch.sh add failed (exit {add.returncode}); nothing was marked proposed, "
            f"the next suggest proposes these rules again", 1)
    for pid, (rule, r) in zip(ids, new):
        state["rules"][rule] = {"id": pid, "item": did, "scope": r["scope"], "status": "proposed",
                                "count": r["count"], "proposed": time.strftime("%Y-%m-%d %H:%M")}
    state["next"] += len(new)
    write_json(state_path(d), state)
    print(did)
    print("\n".join(lines))


def pick(state, ids):
    proposed = {k: v for k, v in state["rules"].items() if v["status"] == "proposed"}
    if ids == ["all"]:
        return list(proposed)
    out, unknown = [], []
    for i in ids:
        hit = [k for k, v in proposed.items() if v["id"] == i or v.get("item") == i]
        if hit:
            out += [k for k in hit if k not in out]
        elif not re.fullmatch(r"D\d+", i):  # an item with nothing left proposed is fine
            unknown.append(i)
    if unknown:
        names = " ".join(sorted(v["id"] for v in proposed.values())) or "none"
        die(f"not a proposed rule: {' '.join(unknown)} (proposed: {names})")
    return out


def cmd_apply(args):
    if len(args) < 2:
        die("apply needs <dir> and P<n>..., D<n> or all")
    d = args[0]
    state = load_state(d)
    rules = pick(state, args[1:])
    glob_rules = [r for r in rules if state["rules"][r]["scope"] == "global"]
    proj_rules = [r for r in rules if state["rules"][r]["scope"] == "project"]
    if glob_rules:
        settings = read_json(USER_SETTINGS, {})
        backup_settings()
        allow = settings.setdefault("permissions", {}).setdefault("allow", [])
        allow.extend(r for r in glob_rules if r not in allow)
        write_json(USER_SETTINGS, settings)
    if proj_rules:
        lst = read_json(PROJECT_ALLOW, [])
        lst.extend(r for r in proj_rules if r not in lst)
        write_json(PROJECT_ALLOW, lst)
    for r in rules:
        state["rules"][r]["status"] = "applied"
        target = USER_SETTINGS if r in glob_rules else PROJECT_ALLOW
        print(f"applied {state['rules'][r]['id']} {r} -> {target}")
    write_json(state_path(d), state)


def cmd_decline(args):
    if len(args) < 2:
        die("decline needs <dir> and P<n>..., D<n> or all")
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
    handlers = {"log": lambda a: cmd_log(), "seed": lambda a: cmd_seed(),
                "suggest": cmd_suggest, "apply": cmd_apply, "decline": cmd_decline}
    if cmd not in handlers:
        die(f"unknown command: {cmd}")
    handlers[cmd](args)


if __name__ == "__main__":
    main()
