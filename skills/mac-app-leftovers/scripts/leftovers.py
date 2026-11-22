#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Find and clean files left behind by macOS apps and tools that are no longer installed.

Usage:
  leftovers.py scan  [--json] [--min-kb N]
  leftovers.py clean [--app NAME ...] [--include-review] [--yes]

scan  lists leftovers grouped by app with sizes. Nothing is changed.
clean re-runs the scan, then moves the selected leftovers to the Trash.
      Without --yes it only prints what it would move (dry run).

Confidence levels:
  high    reverse-DNS bundle-ID entries (Preferences, Containers, HTTPStorages, ...)
          and LaunchAgents whose program no longer exists.
  review  name-based guesses (Caches, Application Support, Logs, ~/.dotfolders).
          These are only cleaned with --include-review.
Standard library only.
"""
from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
LIB = HOME / "Library"

# Opaque bundle IDs whose owner name is not visible in the ID.
ALIASES = {
    "com.todesktop.230313mzl4w4u92": "Cursor",
    "com.facebook.archon": "Messenger",
    "dev.kdrag0n.macvirt": "OrbStack",
    "com.philandro.anydesk": "AnyDesk",
    "com.exafunction.windsurf": "Windsurf",
    "com.fournova.tower3": "Tower",
    "com.danpristupov.fork": "Fork",
    "com.yuki.devtoys": "DevToys",
    "com.amazon.codewhisperer": "Amazon Q",
}

# macOS components and developer-tool caches that are not app leftovers.
NOT_LEFTOVERS = {
    # system
    "siritts", "geoservices", "passkit", "animoji", "askpermissiond", "fnfrangecache",
    "gamekit", "pfscenetaxonomydataindex", "intelligenceflow", "ilifemediabrowser",
    "appplaceholdersyncd", "jetpackcache", "mbuseragent", "diagnosticreports",
    "sesstorage", "cloudkit", "familycircle", "knowledge", "callhistorydb",
    "addressbook", "crashreporter", "mobilesync", "syncservices", "fileprovider",
    "diskimages", "dock", "icloud", "clouddocs", "safari", "mail", "quicklook",
    "appstore", "metadata", "photos", "keyboardservices", "spellingcache", "caches",
    "icdd", "ssu", "amsdatamigratortool", "qplcrashresilient", "baseband",
    "privacypreservingmeasurement",
    # developer tool caches (live tools, regenerated on demand)
    "msplaywright", "msplaywrightgo", "homebrew", "gobuild", "typescript", "nodegyp",
    "electron", "nextswc", "jedi", "pip", "pippackages", "yarn", "pnpm", "npm",
    "cocoapods", "orgswiftswiftpm", "swiftpm", "flutterengine", "vitest", "turborepo",
    "fanal", "statsigcache", "segment", "googleheartbeatstorage", "cef", "mozilla",
    "devbiomejsbiome", "comturborepoturborepo", "uv", "ruff", "deno", "bun", "pypoetry",
    "composer", "gradle", "kotlin", "golangcilint", "sccache", "puppeteer", "huggingface",
}

DOTFOLDER_KEEP = {
    "config", "local", "cache", "ssh", "zshsessions", "claude", "npm", "cargo", "rustup",
    "docker", "vscode", "gnupg", "ohmyzsh", "nvm", "bun", "pnpm", "yarn", "gradle", "m2",
    "android", "cursor", "codex", "agentkit", "kube", "aws", "azure", "gcloud", "terraformd",
    "ipython", "jupyter", "matplotlib", "conda", "pyenv", "rbenv", "gem", "bundle",
    "cocoapods", "swiftpm", "dotnet", "nuget", "pki", "subversion", "vim", "tmux", "trash",
    "agents", "copilot", "pnpmstate", "homebrew", "gk", "zcompdump", "vscodeshared",
}

TLDS = {"com", "org", "net", "io", "dev", "app", "co", "me", "ai", "us", "de", "uk", "ch", "group"}
BUNDLE_DIRS = ["Preferences", "Containers", "Group Containers", "Saved Application State",
               "HTTPStorages", "WebKit", "Caches", "Logs", "Application Support"]
NAME_DIRS = ["Caches", "Logs", "Application Support"]
TEAM_ID = re.compile(r"^[A-Z0-9]{10}\.")
# Only apps create these, so a bundle-ID entry here proves an app existed.
APP_ONLY_DIRS = {"Containers", "Group Containers", "Saved Application State", "HTTPStorages", "WebKit"}
# Vendor-shared components that stay valid while any app from the same vendor is installed.
SHARED_WORDS = {"shared", "common", "autoupdate", "oneauth", "helper", "entrabroker", "updater"}


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def strip_bundle(name: str) -> str:
    """'W5W395V82Y.group.com.nordvpn.savedState' -> 'com.nordvpn'."""
    for suffix in (".plist", ".savedState", ".binarycookies", ".ShipIt"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
    name = TEAM_ID.sub("", name)
    if name.startswith("group."):
        name = name[6:]
    return name


def is_bundle_id(name: str) -> bool:
    parts = name.split(".")
    return len(parts) >= 3 and parts[0].lower() in TLDS and all(parts)


# ---------------------------------------------------------------- installed inventory

def _run(cmd: list[str]) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=120).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def collect_installed() -> dict:
    apps = set(_run(["mdfind", "kMDItemContentType == 'com.apple.application-bundle'"]).splitlines())
    for root in ("/Applications", str(HOME / "Applications"), "/System/Applications",
                 "/Library/Application Support"):
        for dirpath, dirnames, _ in os.walk(root):
            depth = dirpath[len(root):].count(os.sep)
            for d in list(dirnames):
                if d.endswith(".app"):
                    apps.add(os.path.join(dirpath, d))
            if depth >= 3:
                dirnames[:] = []
            else:
                dirnames[:] = [d for d in dirnames if not d.endswith(".app")]
    ids, names = set(), set()
    for a in apps:
        names.add(norm(Path(a).stem))
        try:
            with open(os.path.join(a, "Contents", "Info.plist"), "rb") as f:
                info = plistlib.load(f)
        except Exception:
            continue
        bid = str(info.get("CFBundleIdentifier", "")).lower()
        if bid:
            ids.add(bid)
        for key in ("CFBundleName", "CFBundleDisplayName"):
            if info.get(key):
                names.add(norm(str(info[key])))
    # command-line tools on PATH, Homebrew formulae/casks, system components
    for d in os.environ.get("PATH", "").split(":") + ["/opt/homebrew/bin", "/usr/local/bin",
                                                       "/usr/libexec", "/usr/sbin"]:
        try:
            names |= {norm(f) for f in os.listdir(d)}
        except OSError:
            pass
    for fw in ("/System/Library/Frameworks", "/System/Library/PrivateFrameworks"):
        try:
            names |= {norm(f.removesuffix(".framework")) for f in os.listdir(fw)}
        except OSError:
            pass
    if shutil.which("brew"):
        names |= {norm(x) for x in _run(["brew", "list", "-1"]).split()}
    names.discard("")
    id_words = set()
    for bid in ids:
        id_words |= {norm(p) for p in bid.split(".")[1:] if len(norm(p)) >= 4}
    return {"ids": ids, "names": names, "id_words": id_words - {norm(t) for t in TLDS}}


def bundle_installed(bid: str, inv: dict, vendor_shared: bool = False) -> bool:
    b = bid.lower()
    if b.startswith(("com.apple.", "apple.")):
        return True
    parts = b.split(".")
    vendor = ".".join(parts[:2])
    if vendor_shared or (len(parts) > 2 and norm(parts[2]) in SHARED_WORDS):
        if any(i.startswith(vendor + ".") for i in inv["ids"]):
            return True
    prefix3 = ".".join(parts[:3])
    for i in inv["ids"]:
        if b == i or b.startswith(i + ".") or i.startswith(b + ".") or i.startswith(prefix3 + "."):
            return True
        if ".".join(i.split(".")[:3]) == prefix3:
            return True
    # 'com.microsoft.teams' vs installed 'com.microsoft.teams2'
    # 'com.spotify.client-launcher' belongs to the installed Spotify app
    if any(len(norm(w)) >= 4 and norm(w) in inv["names"] for w in parts[1:]):
        return True
    return any(len(w) >= 4 and any(iw.startswith(w) for iw in inv["id_words"])
               for w in (norm(p) for p in parts[2:]))


def name_installed(name: str, inv: dict) -> bool:
    k = norm(name)
    if len(k) < 3 or k in NOT_LEFTOVERS or name.lower().startswith(("com.apple", "apple")):
        return True
    if k in inv["names"] or k in inv["id_words"]:
        return True
    # 'ZaloData' belongs to 'Zalo'; 'JetBrains' belongs to com.jetbrains.datagrip
    return any(len(n) >= 4 and (k.startswith(n) or n.startswith(k) and len(k) >= 5)
               for n in inv["names"] | inv["id_words"])


# ---------------------------------------------------------------- scanning

def du_kb(p: Path) -> int:
    out = _run(["du", "-sk", str(p)])
    try:
        return int(out.split()[0])
    except (IndexError, ValueError):
        return 0


GENERIC_PRODUCT = {"browser", "desktop", "app", "mac", "macos", "client", "launcher", "helper",
                   "developerid", "loginhelper", "storage"}


def group_key(bid_or_name: str) -> tuple[list[str], str]:
    """Return (merge keys, display label). Bundle IDs match on vendor and product names."""
    low = bid_or_name.lower()
    for alias_id, label in ALIASES.items():
        if low == alias_id or low.startswith(alias_id + "."):
            return [norm(label), norm(alias_id.split(".")[1])], label
    if is_bundle_id(bid_or_name):
        parts = bid_or_name.split(".")
        vendor, product = parts[1], parts[2]
        keys = [norm(vendor)] if len(norm(vendor)) >= 4 else []
        if norm(product) not in GENERIC_PRODUCT:
            keys.append(norm(product))
        generic_vendor = norm(vendor) in {"electron", "github", "google", "microsoft"} or len(vendor) <= 3
        label = product if generic_vendor else vendor
        return keys or [norm(bid_or_name)], label
    label = bid_or_name.lstrip(".")
    return [norm(label)], label


def scan(inv: dict) -> list[dict]:
    items: list[dict] = []

    def add(path: Path, owner: str, confidence: str, kind: str):
        keys, label = group_key(owner)
        items.append({"path": str(path), "keys": keys, "app": label, "confidence": confidence,
                      "kind": kind})

    seen: set[str] = set()
    for sub in BUNDLE_DIRS:
        d = LIB / sub
        if not d.is_dir():
            continue
        for entry in os.listdir(d):
            bid = strip_bundle(entry)
            if is_bundle_id(bid) and not bundle_installed(bid, inv, sub == "Group Containers"):
                add(d / entry, bid, "high" if sub in APP_ONLY_DIRS else "review", sub)
                seen.add(str(d / entry))
    for sub in NAME_DIRS:
        d = LIB / sub
        if not d.is_dir():
            continue
        for entry in os.listdir(d):
            p = d / entry
            if str(p) in seen or entry.startswith(".") or "." in entry.strip("."):
                continue
            if p.is_dir() and not name_installed(entry, inv):
                add(p, entry, "review", sub)
    la = LIB / "LaunchAgents"
    if la.is_dir():
        for entry in os.listdir(la):
            p = la / entry
            try:
                with open(p, "rb") as f:
                    pl = plistlib.load(f)
            except Exception:
                continue
            prog = pl.get("Program") or (pl.get("ProgramArguments") or [None])[0]
            if prog and not os.path.exists(os.path.expanduser(prog)):
                add(p, strip_bundle(entry), "high", "LaunchAgents (program missing)")
    for entry in os.listdir(HOME):
        p = HOME / entry
        k = norm(entry)
        if (entry.startswith(".") and p.is_dir() and not p.is_symlink() and k
                and k not in DOTFOLDER_KEEP and not name_installed(entry, inv)):
            add(p, entry, "review", "home dotfolder")

    for it in items:
        it["kb"] = du_kb(Path(it["path"]))
    return merge_groups(items)


def _related(a: str, b: str) -> bool:
    return len(a) >= 5 and len(b) >= 5 and (a.startswith(b) or b.startswith(a)) or a == b


def merge_groups(items: list[dict]) -> list[dict]:
    """Merge items that share a vendor or product name ('RedisInsight' with 'org.RedisLabs.RedisInsight-V2')."""
    groups: list[dict] = []
    for it in items:
        g = next((g for g in groups if any(_related(a, b) for a in it["keys"] for b in g["keys"])), None)
        if g is None:
            g = {"app": it["app"], "kb": 0, "items": [], "keys": set()}
            groups.append(g)
        g["keys"] |= set(it["keys"])
        g["items"].append(it)
        g["kb"] += it["kb"]
    groups.sort(key=lambda g: g["kb"], reverse=True)
    for g in groups:
        g["keys"] = sorted(g["keys"])
        # One app-only entry (container, web storage, dead LaunchAgent) proves the whole group.
        g["confidence"] = "high" if any(i["confidence"] == "high" for i in g["items"]) else "review"
        for i in g["items"]:
            i["confidence"] = g["confidence"]
        g["items"].sort(key=lambda i: i["kb"], reverse=True)
    return groups


def stale_background_items() -> list[str]:
    """Login/background items (BTM) whose app no longer exists. Read-only."""
    out = _run(["sfltool", "dumpbtm"])
    missing = set()
    for m in re.finditer(r"^\s+URL:\s*(\S.*)$", out, re.M):
        url = m.group(1).strip()
        path = url[7:] if url.startswith("file://") else url
        path = re.sub(r"%([0-9A-Fa-f]{2})", lambda x: chr(int(x.group(1), 16)), path).rstrip("/")
        # BTM records the home folder as /Users/<uid>
        path = path.replace(f"/Users/{os.getuid()}/", f"{HOME}/", 1)
        if path.startswith("/") and not os.path.exists(path):
            missing.add(path)
    return sorted(missing)


# ---------------------------------------------------------------- output

def fmt(kb: int) -> str:
    return f"{kb / 1024 / 1024:.1f} GB" if kb >= 1024 * 1024 else f"{kb / 1024:.1f} MB"


def short(p: str) -> str:
    return p.replace(str(HOME), "~", 1)


def print_report(groups: list[dict], btm: list[str]) -> None:
    total = sum(g["kb"] for g in groups)
    print(f"Leftovers from {len(groups)} uninstalled apps/tools, {fmt(total)} total\n")
    for g in groups:
        print(f"## {g['app']}  {fmt(g['kb'])}  [{g['confidence']}]")
        for it in g["items"]:
            print(f"   {fmt(it['kb']):>9}  {it['confidence']:<6}  {short(it['path'])}")
        print()
    if btm:
        print("Login items pointing to apps that no longer exist:")
        for p in btm:
            print(f"   {p}")
        print("   Fix: sudo sfltool resetbtm, then restart (other background apps may ask again).\n")
    print("high = bundle-ID match, safe to clean. review = name-based guess, check before cleaning.")


# ---------------------------------------------------------------- cleaning

def allowed(p: Path) -> bool:
    try:
        rel = p.resolve().relative_to(HOME)
    except ValueError:
        return False
    first = rel.parts[0] if rel.parts else ""
    return first == "Library" and len(rel.parts) >= 3 or (first.startswith(".") and len(rel.parts) == 1)


def to_trash(p: Path) -> str | None:
    """Move to ~/.Trash; fall back to Finder for macOS-protected containers. Returns error or None."""
    trash = HOME / ".Trash"
    dest = trash / p.name
    if dest.exists():
        dest = trash / f"{p.name} {time.strftime('%H.%M.%S')}"
    try:
        os.rename(p, dest)
        return None
    except OSError:
        pass
    script = f'tell application "Finder" to delete (POSIX file "{p}" as alias)'
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    return None if r.returncode == 0 else (r.stderr.strip() or "permission denied")


def clean(groups: list[dict], apps: list[str], include_review: bool, yes: bool) -> int:
    wanted = {norm(a) for a in apps}
    chosen = []
    for g in groups:
        if wanted and not ({norm(g["app"])} | set(g["keys"])) & wanted:
            continue
        for it in g["items"]:
            if it["confidence"] == "high" or include_review or wanted:
                chosen.append((g["app"], it))
    if not chosen:
        print("Nothing selected to clean.")
        return 0
    total = sum(it["kb"] for _, it in chosen)
    print(f"{'Moving' if yes else 'Would move'} {len(chosen)} items ({fmt(total)}) to the Trash:")
    failures = []
    for app, it in chosen:
        p = Path(it["path"])
        if not allowed(p):
            failures.append((p, "outside ~/Library and ~/.dotfolders, skipped"))
            continue
        print(f"   {app:<20} {fmt(it['kb']):>9}  {short(str(p))}")
        if not yes:
            continue
        if it["kind"].startswith("LaunchAgents"):
            label = p.stem
            subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}/{label}"],
                           capture_output=True)
        err = to_trash(p)
        if err:
            failures.append((p, err))
    if not yes:
        print("\nDry run. Re-run with --yes to move these to the Trash.")
        return 0
    if failures:
        print("\nNot moved:")
        for p, err in failures:
            print(f"   {short(str(p))}: {err}")
        print("Grant Full Disk Access to your terminal app (System Settings > Privacy & Security),"
              " restart it, and run clean again; or drag these to the Trash in Finder.")
    print("\nDone. Empty the Trash to free the space.")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan", help="list leftovers with sizes (read-only)")
    s.add_argument("--json", action="store_true")
    s.add_argument("--min-kb", type=int, default=0, help="hide apps smaller than this")
    c = sub.add_parser("clean", help="move leftovers to the Trash (dry run without --yes)")
    c.add_argument("--app", action="append", default=[], help="only this app (repeatable)")
    c.add_argument("--include-review", action="store_true", help="also clean review items")
    c.add_argument("--yes", action="store_true", help="actually move files")
    args = ap.parse_args()

    if sys.platform != "darwin":
        print("macOS only.", file=sys.stderr)
        return 2
    groups = scan(collect_installed())
    if args.cmd == "scan":
        groups = [g for g in groups if g["kb"] >= args.min_kb]
        btm = stale_background_items()
        if args.json:
            print(json.dumps({"groups": groups, "stale_login_items": btm}, indent=2))
        else:
            print_report(groups, btm)
        return 0
    return clean(groups, args.app, args.include_review, args.yes)


if __name__ == "__main__":
    sys.exit(main())
