#!/usr/bin/env python3
"""
bootstrap.py — Dotfiles manager for Ben's machines.

OVERVIEW
--------
This script is the single entry point for setting up and maintaining any of
Ben's machines (macOS or Arch Linux). It handles three concerns:

  1. Packages   — installing formulae/casks (brew) or AUR packages (yay)
  2. Dotfiles   — syncing the overlay directory (home/<user>/) with $HOME,
                  and etc/ with /etc on Linux
  3. Tooling    — shell plugins, tmux plugins, etc. declared in setup.toml

HOW SYNC DECIDES WHO IS NEWER
-----------------------------
Timestamps are useless here: git clone/checkout/pull stamp every file with
"now", and copying stamps the destination. So instead of mtimes, every file is
compared by CONTENT, three ways:

  repo   — the file in the overlay
  live   — the file on this machine
  base   — the content both sides agreed on at the last sync on this machine,
           recorded in ~/.local/state/dotfiles/state.json

  live == repo            → in sync
  live missing            → new, deploy it
  live == base            → only the repo changed     → deploy (safe)
  repo == base            → only this machine changed → save into repo (safe)
  neither                 → both changed              → conflict, you choose

On a machine with no state yet (first run), a file whose live content matches
any version in the file's git history is treated as "repo is newer"; anything
else is a conflict, because there is no way to know which side is newer.

Conflicts are never resolved silently. Interactively you can view the diff,
take either side, or merge in `nvim -d`. Non-interactively they are skipped
and listed. Anything overwritten on this machine is backed up first to
~/dotfiles.bak/<timestamp>/.

USAGE
-----
  python3 bootstrap.py                 → interactive TUI
  python3 bootstrap.py sync            → git pull, then sync both directions
  python3 bootstrap.py install         → full setup of a new machine
  python3 bootstrap.py apply           → repo → machine only   (alias: copy)
  python3 bootstrap.py save            → machine → repo only   (alias: pull)
  python3 bootstrap.py status          → show drift, change nothing
  python3 bootstrap.py diff [path...]  → show diffs for drifted files
  python3 bootstrap.py add <path...>   → start tracking files or directories

STRUCTURE
---------
  packages/brew.txt        formulae for all Macs
  packages/brew-casks.txt  cask apps for all Macs
  packages/arch.txt        packages for all Arch machines
  setup.toml               fish/tmux plugin declarations
  home/<user>/             dotfile overlay (mirrors $HOME structure)
  etc/                     /etc overlay (Linux only, applied with sudo;
                           *.md files are notes and are not deployed)
  themes/                  colour schemes (catppuccin submodule etc.)
"""
from __future__ import annotations

import os, sys, subprocess, shutil, platform
from pathlib import Path

# ── dependency bootstrap ──────────────────────────────────────────────────────
# This block runs before any third-party imports so the script is self-contained
# on a fresh machine. It installs rich, questionary, and (on Python < 3.11) tomli,
# then re-execs the current process so the new packages are on sys.path.
# We cannot simply importlib.reload after pip because sys.path is already frozen.

def _ensure_deps() -> None:
    """Install TUI/TOML deps if missing, then re-exec so they're importable."""
    import importlib.util
    needed = ["rich", "questionary"]
    if sys.version_info < (3, 11):
        # tomllib was added to stdlib in 3.11; older Pythons need the backport
        needed.append("tomli")
    missing = [p for p in needed if not importlib.util.find_spec(p)]
    if not missing:
        return
    print(f"[bootstrap] Installing missing deps: {', '.join(missing)} ...")
    try:
        # --user avoids needing root; --quiet suppresses pip's noisy output
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "--quiet", "--user"] + missing,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        # PEP 668 (Arch, Ubuntu 23+, Homebrew Python) marks the interpreter as
        # externally managed, requiring --break-system-packages for user installs
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "--quiet",
             "--break-system-packages", "--user"] + missing
        )
    # Re-exec this process with the same args; now deps will be importable
    os.execv(sys.executable, [sys.executable] + sys.argv)

_ensure_deps()

# tomllib is stdlib on 3.11+; fall back to the tomli backport below that
try:
    import tomllib
except ImportError:
    import tomli as tomllib  # type: ignore

import difflib, fnmatch, hashlib, json, socket, time
from dataclasses import dataclass, field
from typing import Callable
from rich.console import Console
from rich.panel import Panel
from rich.syntax import Syntax
from rich.text import Text
import questionary

console = Console()

# ── paths ─────────────────────────────────────────────────────────────────────
DOTFILES_DIR = Path(__file__).parent.resolve()
USERNAME     = os.environ.get("USER", os.environ.get("LOGNAME", "benk"))

# Every run that overwrites something gets its own backup folder, so an older
# backup is never clobbered by a newer one
RUN_STAMP  = time.strftime("%Y%m%d-%H%M%S")
BACKUP_DIR = Path.home() / "dotfiles.bak" / RUN_STAMP

# Per-machine record of the last-synced content of every file (see docstring)
STATE_FILE = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    / "dotfiles" / "state.json"
)

# Prompts only make sense with a human on the other end of stdin
INTERACTIVE = sys.stdin.isatty()

# ── setup.toml ────────────────────────────────────────────────────────────────
# setup.toml holds tooling that doesn't belong in a plain text package list:
# fish plugins, tmux plugins, and future post-install hooks.
# Packages stay in packages/*.txt so they remain easy to diff and grep.

def _load_setup() -> dict:
    """Load setup.toml from the repo root. Returns {} if the file doesn't exist."""
    p = DOTFILES_DIR / "setup.toml"
    if not p.exists():
        return {}
    with open(p, "rb") as f:
        return tomllib.load(f)

SETUP = _load_setup()

# ── OS detection ──────────────────────────────────────────────────────────────

def detect_os() -> str:
    """
    Detect the current operating system.
    Returns one of: 'macos', 'arch', 'linux', 'unknown'.
    """
    if platform.system() == "Darwin":
        return "macos"
    if Path("/etc/arch-release").exists():
        return "arch"
    if Path("/etc/os-release").exists():
        return "linux"
    return "unknown"

OS = detect_os()
IS_LINUX = OS in ("arch", "linux")

# ── overlay resolution ────────────────────────────────────────────────────────
# OS is the ONLY variation axis — all Macs are identical, all Arch machines
# are identical. We fall back through home/<username>/ → home/benk/.

def overlay_home() -> Path:
    """
    Return the dotfile overlay directory for the current user.
    Checks home/<username>/ first, then falls back to home/benk/.
    Creates home/<username>/ if neither exists.
    """
    for candidate in (USERNAME, "benk"):
        p = DOTFILES_DIR / "home" / candidate
        if p.is_dir():
            return p
    # No overlay found — create one for this user rather than silently using benk/
    p = DOTFILES_DIR / "home" / USERNAME
    p.mkdir(parents=True, exist_ok=True)
    return p

# ── what gets synced ──────────────────────────────────────────────────────────
# Some paths in the overlay only make sense on specific OSes; they are skipped
# everywhere else. ~/.dotignore adds per-machine exclusions on top.
#
# Format: { "path/in/overlay/": {oses it belongs to} }

OS_ONLY: dict[str, set[str]] = {
    "Library/":         {"macos"},           # iTerm2 prefs, macOS app support
    ".config/wezterm/": {"arch", "linux"},   # WezTerm on Linux, iTerm2 on macOS
}

# Never deployed: OS litter, placeholders that only exist so git keeps a dir
JUNK_NAMES = {".DS_Store", ".gitkeep"}
JUNK_DIRS  = {"__pycache__"}

def _load_dotignore() -> list[str]:
    """
    Read ~/.dotignore and return patterns to exclude from syncing on this machine.
    Each non-blank, non-comment line is a pattern (see _ignored for the syntax).
    """
    p = Path.home() / ".dotignore"
    if not p.exists():
        return []
    return [
        ln.strip() for ln in p.read_text().splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    ]

def _ignored(rel: str, patterns: list[str]) -> bool:
    """
    gitignore-style matching of an overlay-relative path against patterns:
      'dir/'           matches everything under any directory named dir
      'a/b' or '/a/b'  contains a slash → anchored at the overlay root
      '*.log'          no slash → matches any single path component
    Globs (* ? [..]) work in all forms.
    """
    parts = rel.split("/")
    for raw in patterns:
        pat = raw.strip()
        dir_only = pat.endswith("/")
        pat = pat.strip("/")
        if not pat:
            continue
        # Directory-only patterns may not match the file name itself
        n = len(parts) - 1 if dir_only else len(parts)
        if "/" in raw.strip().rstrip("/"):
            if any(fnmatch.fnmatchcase("/".join(parts[:i]), pat) for i in range(1, n + 1)):
                return True
        elif any(fnmatch.fnmatchcase(part, pat) for part in parts[:n]):
            return True
    return False

@dataclass
class Scope:
    """One overlay/destination pair that gets synced."""
    name:     str              # key in the state file: 'home' or 'etc'
    repo:     Path             # overlay root inside the repo
    live:     Path             # where it is deployed
    sudo:     bool             # whether writing to `live` needs root
    excludes: list[str]        # _ignored() patterns

    def display(self, rel: str) -> str:
        """How to show a path from this scope to the user."""
        return f"~/{rel}" if self.name == "home" else f"/etc/{rel}"

def home_scope() -> Scope:
    excludes = [p for p, oses in OS_ONLY.items() if OS not in oses]
    return Scope("home", overlay_home(), Path.home(), False, excludes + _load_dotignore())

def etc_scope() -> Scope | None:
    """
    The /etc overlay. Linux only — the files in etc/ (fstab, nginx.conf, ...)
    describe the Arch machines and must never land in a Mac's /etc.
    """
    etc_dir = DOTFILES_DIR / "etc"
    if not IS_LINUX or not etc_dir.is_dir():
        return None
    scope = Scope("etc", etc_dir, Path("/etc"), True, ["*.md"])
    return scope if tracked_files(scope) else None

def all_scopes() -> list[Scope]:
    return [s for s in (home_scope(), etc_scope()) if s]

def tracked_files(scope: Scope) -> list[str]:
    """Every overlay-relative file path in the scope that should be synced."""
    out = []
    for p in sorted(scope.repo.rglob("*")):
        if p.is_dir() and not p.is_symlink():
            continue
        rel = p.relative_to(scope.repo).as_posix()
        parts = rel.split("/")
        if parts[-1] in JUNK_NAMES or JUNK_DIRS.intersection(parts[:-1]):
            continue
        if _ignored(rel, scope.excludes):
            continue
        out.append(rel)
    return out

# ── content hashing ───────────────────────────────────────────────────────────
# Files are identified by git's blob hash (sha1 of "blob <len>\0<content>").
# Using git's scheme means a hash of a live file can be looked up directly in
# the repo's history, which is what lets a first run tell "old version of a
# committed file" apart from "edited on this machine". Symlinks hash their
# target path, which is also exactly what git stores for them.

def _blob_hash(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()

def _read(path: Path, *, sudo: bool = False) -> bytes | None:
    """
    File content (or symlink target) as bytes, None if the path doesn't exist.
    Root-only files are read with `sudo cat` when `sudo` is set.
    Raises IsADirectoryError if the path is a real directory.
    """
    if path.is_symlink():
        return os.readlink(path).encode()
    if not path.exists():
        return None
    if path.is_dir():
        raise IsADirectoryError(path)
    try:
        return path.read_bytes()
    except PermissionError:
        if not sudo:
            raise
        return subprocess.run(
            ["sudo", "cat", str(path)], check=True, capture_output=True,
        ).stdout

_history_cache: dict[str, dict[str, set[str]]] = {}

def _git_history(prefix: Path) -> dict[str, set[str]]:
    """
    Map each repo-relative path under `prefix` → every blob hash it has ever
    had in git. One `git log --raw` covers the whole overlay.
    """
    key = str(prefix)
    if key in _history_cache:
        return _history_cache[key]
    history: dict[str, set[str]] = {}
    try:
        result = subprocess.run(
            ["git", "-c", "core.quotePath=off", "log", "--format=", "--raw",
             "--no-abbrev", "--no-renames", "--", prefix.relative_to(DOTFILES_DIR).as_posix()],
            cwd=DOTFILES_DIR, capture_output=True, text=True, timeout=60,
        )
        # Lines look like ":100644 100644 <old blob> <new blob> M\t<path>"
        for line in result.stdout.splitlines():
            if not line.startswith(":") or "\t" not in line:
                continue
            meta, path = line.split("\t", 1)
            fields = meta.split()
            history.setdefault(path, set()).update(fields[2:4])
    except (OSError, subprocess.TimeoutExpired, ValueError):
        pass
    for blobs in history.values():
        blobs.discard("0" * 40)   # the "file didn't exist" side of add/delete
    _history_cache[key] = history
    return history

# ── sync state ────────────────────────────────────────────────────────────────

def _load_state() -> dict[str, dict[str, str]]:
    """{scope name: {rel path: blob hash at last sync}}; {} on first run."""
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        return {}

def _save_state(state: dict[str, dict[str, str]]) -> None:
    """Write atomically so an interrupted run never leaves half a file."""
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1, sort_keys=True))
    tmp.replace(STATE_FILE)

# ── classification ────────────────────────────────────────────────────────────

@dataclass
class Entry:
    """One tracked file and how its two sides relate."""
    rel:   str
    kind:  str                 # same | new | repo | local | conflict | blocked
    repo:  bytes = b""
    live:  bytes | None = None
    why:   str = ""            # human explanation, for conflicts and odd cases

KIND_ORDER = ["new", "repo", "local", "conflict", "blocked"]
KIND_LABEL = {
    "new":      ("[blue]+[/blue]",        "not on this machine yet"),
    "repo":     ("[cyan]↓[/cyan]",        "changed in the repo"),
    "local":    ("[yellow]↑[/yellow]",    "changed on this machine"),
    "conflict": ("[red]![/red]",          "need you to choose"),
    "blocked":  ("[red]✗[/red]",          "can't be synced"),
}

def classify(scope: Scope, rel: str, base: dict[str, str]) -> Entry:
    """Work out the three-way state of one file (see module docstring)."""
    repo = _read(scope.repo / rel) or b""
    try:
        live = _read(scope.live / rel, sudo=scope.sudo)
    except IsADirectoryError:
        return Entry(rel, "blocked", repo, None, "a directory exists at this path")
    except (PermissionError, subprocess.CalledProcessError) as e:
        return Entry(rel, "blocked", repo, None, f"unreadable: {e}")

    if live is None:
        return Entry(rel, "new", repo, None)
    repo_h, live_h = _blob_hash(repo), _blob_hash(live)
    if repo_h == live_h:
        return Entry(rel, "same", repo, live)

    if rel in base:
        if live_h == base[rel]:
            return Entry(rel, "repo", repo, live)
        if repo_h == base[rel]:
            return Entry(rel, "local", repo, live)
        return Entry(rel, "conflict", repo, live, "both sides changed since the last sync")

    # No record for this file on this machine — fall back to git history
    repo_path = (scope.repo / rel).relative_to(DOTFILES_DIR).as_posix()
    if live_h in _git_history(scope.repo).get(repo_path, ()):
        return Entry(rel, "repo", repo, live, "this machine has an older committed version")
    return Entry(rel, "conflict", repo, live,
                 "never synced on this machine, so there's no telling which side is newer")

def scan(scope: Scope, state: dict[str, dict[str, str]]) -> list[Entry]:
    """
    Classify every tracked file in the scope. Also records the base for files
    already in sync and forgets files no longer in the repo, so the state stays
    accurate even when nothing is copied.
    """
    base = state.setdefault(scope.name, {})
    rels = tracked_files(scope)
    entries = [classify(scope, rel, base) for rel in rels]
    for e in entries:
        if e.kind == "same":
            base[e.rel] = _blob_hash(e.repo)
    for rel in set(base) - set(rels):
        del base[rel]
    return entries

# ── file operations ───────────────────────────────────────────────────────────

def _backup(scope: Scope, rel: str, data: bytes, side: str) -> None:
    """Keep a copy of content about to be overwritten in ~/dotfiles.bak/<run>/."""
    dst = BACKUP_DIR / side / scope.name / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(data)

def deploy(scope: Scope, e: Entry) -> None:
    """Copy the repo version over the live file (backing up the live one)."""
    src, dst = scope.repo / e.rel, scope.live / e.rel
    if e.live is not None:
        _backup(scope, e.rel, e.live, "machine")
    if scope.sudo:
        subprocess.run(["sudo", "mkdir", "-p", str(dst.parent)], check=True)
        subprocess.run(
            ["sudo", "cp", "-P", "--preserve=mode", "--remove-destination", str(src), str(dst)],
            check=True,
        )
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    # Replace links rather than writing through them into whatever they point at
    if dst.is_symlink():
        dst.unlink()
    if src.is_symlink():
        os.symlink(os.readlink(src), dst)
    else:
        shutil.copy2(src, dst)

def capture(scope: Scope, e: Entry) -> None:
    """Copy the live file into the repo (backing up the repo one)."""
    src, dst = scope.live / e.rel, scope.repo / e.rel
    _backup(scope, e.rel, e.repo, "repo")
    if dst.is_symlink():
        dst.unlink()
    if src.is_symlink():
        os.symlink(os.readlink(src), dst)
    else:
        dst.write_bytes(e.live or b"")
        if not scope.sudo:
            shutil.copymode(src, dst)

# ── diffs ─────────────────────────────────────────────────────────────────────

def _is_binary(data: bytes | None) -> bool:
    if data is None:
        return False
    if b"\0" in data[:8192]:
        return True
    try:
        data.decode("utf-8")
        return False
    except UnicodeDecodeError:
        return True

def show_diff(scope: Scope, e: Entry) -> None:
    """Print a coloured unified diff from this machine's version to the repo's."""
    if _is_binary(e.repo) or _is_binary(e.live):
        console.print(
            f"  [dim]{e.rel}: binary file — this machine {len(e.live or b'')} bytes, "
            f"repo {len(e.repo)} bytes[/dim]"
        )
        return
    lines = list(difflib.unified_diff(
        (e.live or b"").decode().splitlines(keepends=True),
        e.repo.decode().splitlines(keepends=True),
        fromfile=f"{scope.display(e.rel)}  (this machine)",
        tofile=f"{(scope.repo / e.rel).relative_to(DOTFILES_DIR)}  (repo)",
    ))
    text = "".join(ln if ln.endswith("\n") else ln + "\n" for ln in lines)
    syntax = Syntax(text, "diff", theme="ansi_dark", background_color="default")
    if len(lines) > console.height - 4 and INTERACTIVE:
        with console.pager(styles=True):
            console.print(syntax)
    else:
        console.print(syntax)

# ── conflict resolution ───────────────────────────────────────────────────────

def _choice(title: str, desc: str, value: str, *, checked: bool = False) -> questionary.Choice:
    """
    A questionary choice with a dimmed description. questionary renders
    prompt_toolkit formatted text, not rich markup, so style it that way.
    """
    return questionary.Choice(
        title=[("", title), ("fg:ansibrightblack", f"  {desc}")],
        value=value, checked=checked,
    )

def resolve(scope: Scope, e: Entry) -> str:
    """
    Ask what to do with a file that can't be synced automatically.
    Returns 'repo' (deploy), 'local' (capture), 'merged' (both sides now
    identical) or 'skip'. Raises KeyboardInterrupt on Ctrl-C.
    """
    can_merge = not scope.sudo and shutil.which("nvim") and not _is_binary(e.repo)
    while True:
        console.print(f"\n  [red]![/red]  [bold]{scope.display(e.rel)}[/bold]  [dim]{e.why}[/dim]")
        choices = [
            _choice("Show diff", "this machine → repo", "diff"),
            _choice("Use the repo version", "overwrite this machine (backed up)", "repo"),
            _choice("Keep this machine's version", "save it into the repo", "local"),
        ]
        if can_merge:
            choices.append(_choice("Merge in nvim -d", "edit both, then re-check", "merge"))
        choices.append(_choice("Skip", "leave both as they are for now", "skip"))
        answer = questionary.select("  What should happen?", choices=choices).ask()
        if answer is None:
            raise KeyboardInterrupt
        if answer == "diff":
            show_diff(scope, e)
            continue
        if answer != "merge":
            return answer
        subprocess.run(["nvim", "-d", str(scope.live / e.rel), str(scope.repo / e.rel)])
        e.repo = _read(scope.repo / e.rel) or b""
        e.live = _read(scope.live / e.rel)
        if e.live is not None and _blob_hash(e.live) == _blob_hash(e.repo):
            return "merged"
        console.print("  [yellow]The two versions still differ.[/yellow]")

# ── sync engine ───────────────────────────────────────────────────────────────

def _print_group(scope: Scope, entries: list[Entry], kind: str, *, limit: int | None = None) -> None:
    icon, label = KIND_LABEL[kind]
    console.print(f"  {icon}  {len(entries)} {label}")
    shown = entries if limit is None else entries[:limit]
    for e in shown:
        note = f"  [dim]({e.why})[/dim]" if e.why and kind in ("conflict", "blocked") else ""
        console.print(f"       [dim]{scope.display(e.rel)}[/dim]{note}")
    if len(shown) < len(entries):
        console.print(f"       [dim]... and {len(entries) - len(shown)} more[/dim]")

def sync_scope(scope: Scope, direction: str) -> list[str]:
    """
    Sync one scope.

    direction:
      'apply' — repo → machine. Files changed on this machine are left alone.
      'save'  — machine → repo. Files changed in the repo are left alone.
      'both'  — everything that can move safely moves; conflicts are asked.

    Returns the repo-relative paths written into the repo (for committing).
    """
    state = _load_state()
    entries = scan(scope, state)
    base = state[scope.name]
    by_kind = {k: [e for e in entries if e.kind == k] for k in KIND_ORDER}
    in_sync = sum(1 for e in entries if e.kind == "same")

    to_deploy  = by_kind["new"] + by_kind["repo"] if direction in ("apply", "both") else []
    to_capture = by_kind["local"] if direction in ("save", "both") else []
    # A plain conflict needs a decision whichever way we're going
    to_resolve = by_kind["conflict"]
    held_back  = (by_kind["local"] if direction == "apply" else []) + \
                 (by_kind["new"] + by_kind["repo"] if direction == "save" else [])

    console.print(
        f"  [bold]{scope.repo.relative_to(DOTFILES_DIR)}[/bold] ⇄ "
        f"[bold]{'~' if scope.name == 'home' else '/etc'}[/bold]  "
        f"[dim]{len(entries)} tracked, {in_sync} in sync[/dim]"
    )
    written: list[str] = []
    # A fresh machine gets hundreds of new files; list them only when few
    quiet_new = len(by_kind["new"]) > 20
    try:
        for e in to_deploy:
            deploy(scope, e)
            base[e.rel] = _blob_hash(e.repo)
            if not (quiet_new and e.kind == "new"):
                console.print(f"  {KIND_LABEL[e.kind][0]}  {scope.display(e.rel)}")
        if quiet_new and to_deploy:
            console.print(f"  {KIND_LABEL['new'][0]}  {len(by_kind['new'])} new files deployed")

        for e in to_capture:
            capture(scope, e)
            base[e.rel] = _blob_hash(e.live or b"")
            written.append((scope.repo / e.rel).relative_to(DOTFILES_DIR).as_posix())
            console.print(f"  {KIND_LABEL['local'][0]}  {scope.display(e.rel)}  [dim]→ repo[/dim]")

        skipped: list[Entry] = []
        for e in to_resolve:
            if not INTERACTIVE:
                skipped.append(e)
                continue
            answer = resolve(scope, e)
            if answer == "repo":
                deploy(scope, e)
                base[e.rel] = _blob_hash(e.repo)
            elif answer == "local":
                capture(scope, e)
                base[e.rel] = _blob_hash(e.live or b"")
                written.append((scope.repo / e.rel).relative_to(DOTFILES_DIR).as_posix())
            elif answer == "merged":
                base[e.rel] = _blob_hash(e.repo)
                written.append((scope.repo / e.rel).relative_to(DOTFILES_DIR).as_posix())
            else:
                skipped.append(e)
    finally:
        # Persist whatever got done, even on Ctrl-C mid-way through conflicts
        _save_state(state)

    if not (to_deploy or to_capture or to_resolve or held_back or by_kind["blocked"]):
        console.print("  [green]✓[/green]  Everything is in sync")
    if skipped:
        _print_group(scope, skipped, "conflict")
        console.print("     [dim]Left as they are — run `bootstrap.py diff` to inspect, "
                      "or sync interactively to choose.[/dim]")
    if held_back:
        hint = "run Save to keep them" if direction == "apply" else "run Apply to deploy them"
        console.print(f"  [dim]·  {len(held_back)} other file(s) differ in the opposite "
                      f"direction ({hint})[/dim]")
    if by_kind["blocked"]:
        _print_group(scope, by_kind["blocked"], "blocked")
    if to_deploy and any(e.live is not None for e in to_deploy):
        console.print(f"  [dim]Overwritten files backed up to {BACKUP_DIR}[/dim]")
    return written

def _offer_commit(paths: list[str]) -> None:
    """After saving into the repo, offer to commit exactly those files."""
    if not paths:
        return
    console.print()
    console.print(f"  [bold]{len(paths)}[/bold] file(s) saved into the repo.")
    if not INTERACTIVE:
        console.print("  [dim]Commit them with: git -C ~/dotfiles commit[/dim]")
        return
    if not questionary.confirm("  Commit them now?", default=True).ask():
        return
    message = questionary.text(
        "  Commit message:", default=f"sync from {socket.gethostname().split('.')[0]}",
    ).ask()
    if not message:
        return
    subprocess.run(["git", "add", "--", *paths], cwd=DOTFILES_DIR, check=True)
    subprocess.run(["git", "commit", "-m", message, "--", *paths], cwd=DOTFILES_DIR)

# ── repo update ───────────────────────────────────────────────────────────────

def update_repo() -> None:
    """
    Fast-forward the dotfiles repo from its upstream (with submodules) so the
    sync works against the latest config. Local uncommitted edits are stashed
    and restored around the pull. Never merges or rebases.
    """
    has_upstream = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "@{upstream}"],
        cwd=DOTFILES_DIR, capture_output=True,
    ).returncode == 0
    if not has_upstream:
        console.print("  [dim]No upstream branch configured — skipping git pull[/dim]")
        return
    r = subprocess.run(
        ["git", "pull", "--ff-only", "--autostash", "--recurse-submodules"],
        cwd=DOTFILES_DIR, capture_output=True, text=True,
    )
    if r.returncode == 0:
        console.print(f"  [green]✓[/green]  {r.stdout.strip().splitlines()[-1] if r.stdout.strip() else 'Up to date'}")
        _history_cache.clear()
    else:
        console.print("  [yellow]![/yellow]  git pull failed — syncing against the local repo as-is")
        console.print(f"  [dim]{r.stderr.strip()}[/dim]")

# ── directory bootstrap ───────────────────────────────────────────────────────

def create_home_dirs() -> None:
    """
    Ensure standard XDG and home directories exist before syncing.
    .ssh must be 700 or SSH will refuse to use it.
    """
    for d in [
        Path.home() / ".config",
        Path.home() / ".local" / "bin",
        Path.home() / ".local" / "share",
        Path.home() / ".local" / "state",
        Path.home() / ".ssh",
    ]:
        d.mkdir(parents=True, exist_ok=True)
    (Path.home() / ".ssh").chmod(0o700)

# ── package file helpers ──────────────────────────────────────────────────────

def _read_packages(path: Path) -> list[str]:
    """
    Read a package list file. Returns an empty list if the file doesn't exist.
    Lines starting with '#' and blank lines are ignored.
    """
    if not path.exists():
        return []
    return [
        ln.strip() for ln in path.read_text().splitlines()
        if ln.strip() and not ln.startswith("#")
    ]

def _missing(wanted: list[str], installed: set[str]) -> list[str]:
    """Packages not yet installed. Tap-qualified names (owner/tap/pkg) match on pkg."""
    return [p for p in wanted if p.rsplit("/", 1)[-1] not in installed]

def _brew_installed(kind: str) -> set[str]:
    return set(subprocess.check_output(["brew", "list", f"--{kind}", "-1"], text=True).split())

def _install_one(cmd: list[str], pkg: str) -> None:
    """
    Run `cmd pkg` and prompt to continue if it fails.
    Exits the whole script if the user says no — a half-installed machine
    is worse than an aborted one.
    """
    console.print(f"  [dim]{' '.join(cmd)} {pkg}[/dim]")
    result = subprocess.run(cmd + [pkg], capture_output=True, text=True)
    if result.returncode != 0:
        console.print(f"  [red][!] Failed to install:[/red] {pkg}")
        console.print(f"  [dim]{result.stderr.strip()[-500:]}[/dim]")
        if not INTERACTIVE or not questionary.confirm("  Continue anyway?", default=False).ask():
            sys.exit(1)

# ── package installation ──────────────────────────────────────────────────────

def install_packages() -> None:
    """Dispatch to the correct package manager based on OS."""
    if OS == "macos":
        _install_brew()
    elif OS == "arch":
        _install_arch()
    else:
        console.print("[yellow]Unknown OS — skipping package install.[/yellow]")
        console.print("[dim]Install packages manually from packages/*.txt[/dim]")

def _install_brew() -> None:
    """
    Install Homebrew if not present, then install whatever is missing from
    brew.txt (formulae) and brew-casks.txt (GUI apps, fonts).
    """
    if not shutil.which("brew"):
        console.print("  [bold]Homebrew not found — installing...[/bold]")
        subprocess.run(
            ["/bin/bash", "-c",
             "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"],
            check=True,
        )
    for kind, file, cmd in [
        ("formula", "brew.txt",       ["brew", "install"]),
        ("cask",    "brew-casks.txt", ["brew", "install", "--cask"]),
    ]:
        wanted  = _read_packages(DOTFILES_DIR / "packages" / file)
        missing = _missing(wanted, _brew_installed(kind))
        console.print(f"  [green]✓[/green]  {len(wanted) - len(missing)}/{len(wanted)} {kind}s already installed")
        for pkg in missing:
            _install_one(cmd, pkg)

def _install_arch() -> None:
    """
    Bootstrap yay (AUR helper) if not present, then install whatever is missing
    from arch.txt using yay (which also handles official repo packages).
    """
    if not shutil.which("yay"):
        console.print("  [bold]yay not found — bootstrapping from AUR...[/bold]")
        subprocess.run(
            ["sudo", "pacman", "-S", "--needed", "--noconfirm", "git", "base-devel"],
            check=True,
        )
        tmp = Path(subprocess.check_output(["mktemp", "-d"]).decode().strip())
        subprocess.run(
            ["git", "clone", "https://aur.archlinux.org/yay.git", str(tmp / "yay")],
            check=True,
        )
        subprocess.run(["makepkg", "-si", "--noconfirm"], cwd=tmp / "yay", check=True)
        shutil.rmtree(tmp)
    wanted    = _read_packages(DOTFILES_DIR / "packages" / "arch.txt")
    installed = set(subprocess.check_output(["pacman", "-Qq"], text=True).split())
    missing   = _missing(wanted, installed)
    console.print(f"  [green]✓[/green]  {len(wanted) - len(missing)}/{len(wanted)} packages already installed")
    for pkg in missing:
        _install_one(["yay", "-S", "--needed", "--noconfirm"], pkg)

# ── shell tooling ─────────────────────────────────────────────────────────────
# "Tooling" means things that aren't packages but need to be set up once:
# tmux plugin manager, oh-my-fish, fisher, and the plugins declared in setup.toml.
# Runs after dotfiles are synced, since tpm reads ~/.tmux.conf and fisher
# reads ~/.config/fish/fish_plugins.

def setup_shell_tooling() -> None:
    """Set up tmux and fish tooling in sequence."""
    _setup_tmux()
    _setup_fish()

def _setup_tmux() -> None:
    """
    Clone tpm (Tmux Plugin Manager) if not present, then install the plugins
    from ~/.tmux.conf and setup.toml [tmux] via tpm's headless install script.

    tpm lives at ~/.tmux/plugins/tpm.
    Plugins are installed to ~/.tmux/plugins/<plugin-name>.
    """
    tpm = Path.home() / ".tmux" / "plugins" / "tpm"
    if not tpm.exists():
        console.print("  Installing tmux plugin manager (tpm)...")
        subprocess.run(
            ["git", "clone", "https://github.com/tmux-plugins/tpm", str(tpm)],
            check=True,
        )
    else:
        console.print("  [green]✓[/green]  tmux plugin manager")

    install_script = tpm / "bin" / "install_plugins"
    if install_script.exists():
        subprocess.run([str(install_script)], capture_output=True)
        console.print("  [green]✓[/green]  tmux plugins")
    else:
        console.print("  [yellow]![/yellow]  Run [dim]<prefix>I[/dim] inside tmux to install plugins")

def _setup_fish() -> None:
    """
    Set up the fish shell plugin ecosystem:
      1. oh-my-fish (OMF) — theming and utility functions
      2. fisher — fish plugin manager
      3. plugins from ~/.config/fish/fish_plugins (`fisher update`) and from
         setup.toml [fish] plugins

    Skipped entirely if fish is not installed on this machine.
    """
    if not shutil.which("fish"):
        console.print("  [dim]fish not installed — skipping fish setup[/dim]")
        return

    omf = Path.home() / ".local" / "share" / "omf"
    if not omf.exists():
        console.print("  Installing oh-my-fish...")
        subprocess.run(
            ["fish", "-c", "curl -L https://get.oh-my.fish > /tmp/omf-install; "
                           "fish /tmp/omf-install --noninteractive --yes"],
            check=True,
        )
    else:
        console.print("  [green]✓[/green]  oh-my-fish")

    if subprocess.run(["fish", "-c", "type -q fisher"], capture_output=True).returncode != 0:
        console.print("  Installing fisher...")
        subprocess.run(
            ["fish", "-c",
             "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/"
             "functions/fisher.fish | source && fisher install jorgebucaran/fisher"],
            check=True,
        )
    else:
        console.print("  [green]✓[/green]  fisher")

    # fish_plugins is fisher's own manifest; `fisher update` installs it exactly
    if (Path.home() / ".config" / "fish" / "fish_plugins").exists():
        subprocess.run(["fish", "-c", "fisher update"], capture_output=True)

    plugins = SETUP.get("fish", {}).get("plugins", [])
    if plugins:
        installed  = set(_fisher_list())
        to_install = [p for p in plugins if p not in installed]
        if to_install:
            console.print(f"  Installing {len(to_install)} fish plugin(s)...")
            subprocess.run(["fish", "-c", f"fisher install {' '.join(to_install)}"], check=True)
    console.print("  [green]✓[/green]  fish plugins")

def _fisher_list() -> list[str]:
    r = subprocess.run(["fish", "-c", "fisher list"], capture_output=True, text=True)
    return r.stdout.split()

# ── status command ────────────────────────────────────────────────────────────
# Status is read-only for your files — it only refreshes the sync state's
# record of files that are already identical on both sides.

def cmd_status() -> None:
    """Show a full drift report: repo, dotfiles, packages, and tooling."""
    console.rule("[bold]Repo[/bold]", style="bright_blue")
    _status_repo()

    console.rule("[bold]Dotfiles[/bold]", style="bright_blue")
    console.print()
    state = _load_state()
    for scope in all_scopes():
        entries = scan(scope, state)
        drift = [e for e in entries if e.kind != "same"]
        console.print(
            f"  [bold]{scope.repo.relative_to(DOTFILES_DIR)}[/bold] ⇄ "
            f"[bold]{'~' if scope.name == 'home' else '/etc'}[/bold]  "
            f"[dim]{len(entries)} tracked, {len(entries) - len(drift)} in sync[/dim]"
        )
        if not drift:
            console.print("  [green]✓[/green]  Everything is in sync")
        for kind in KIND_ORDER:
            group = [e for e in drift if e.kind == kind]
            if group:
                _print_group(scope, group, kind, limit=10)
        console.print()
    _save_state(state)
    console.print(
        "  [dim]Sync moves ↓ and ↑ files and asks about ! files · "
        "diff shows the changes[/dim]\n"
    )

    console.rule("[bold]Packages[/bold]", style="bright_blue")
    _status_packages()

    console.rule("[bold]Tooling[/bold]", style="bright_blue")
    _status_tooling()

    console.rule(style="bright_blue")

def _status_repo() -> None:
    """Uncommitted changes and how the branch compares to its upstream."""
    console.print()
    dirty = subprocess.run(
        ["git", "status", "--porcelain"], cwd=DOTFILES_DIR, capture_output=True, text=True,
    ).stdout.splitlines()
    if dirty:
        console.print(f"  [yellow]●[/yellow]  {len(dirty)} uncommitted change(s) in the repo")
        for ln in dirty[:10]:
            console.print(f"       [dim]{ln}[/dim]")
        if len(dirty) > 10:
            console.print(f"       [dim]... and {len(dirty) - 10} more[/dim]")
    else:
        console.print("  [green]✓[/green]  Working tree clean")
    counts = subprocess.run(
        ["git", "rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
        cwd=DOTFILES_DIR, capture_output=True, text=True,
    )
    if counts.returncode == 0:
        behind, ahead = (int(n) for n in counts.stdout.split())
        if behind or ahead:
            console.print(
                f"  [cyan]⇅[/cyan]  {ahead} commit(s) to push, {behind} to pull  "
                f"[dim](as of the last fetch)[/dim]"
            )
        else:
            console.print("  [green]✓[/green]  Up to date with upstream  [dim](as of the last fetch)[/dim]")
    console.print()

def _status_packages() -> None:
    """
    Compare wanted packages (from packages/*.txt) against what's installed.
    Shows missing packages individually; installed ones are summarised as a count.
    """
    console.print()
    if OS == "macos":
        if not shutil.which("brew"):
            console.print("  [red]✗[/red]  Homebrew is not installed")
            console.print()
            return
        _status_pkg_list("formulae", _read_packages(DOTFILES_DIR / "packages" / "brew.txt"),
                         _brew_installed("formula"))
        _status_pkg_list("casks", _read_packages(DOTFILES_DIR / "packages" / "brew-casks.txt"),
                         _brew_installed("cask"))
    elif IS_LINUX:
        installed = set(subprocess.check_output(["pacman", "-Qq"], text=True).split())
        _status_pkg_list("packages", _read_packages(DOTFILES_DIR / "packages" / "arch.txt"), installed)
    else:
        console.print("  [dim]Package status not supported on this OS[/dim]")
    console.print()

def _status_pkg_list(label: str, wanted: list[str], installed: set[str]) -> None:
    """Print missing packages individually and summarise installed ones as a count."""
    missing = _missing(wanted, installed)
    for p in missing:
        console.print(f"  [red]✗[/red]  {p}  [dim]({label} — not installed)[/dim]")
    console.print(f"  [green]✓[/green]  {len(wanted) - len(missing)}/{len(wanted)} {label} installed")

def _status_tooling() -> None:
    """
    Check whether tmux tpm, oh-my-fish, fisher, and declared plugins are installed.
    Cross-references setup.toml for expected plugin lists.
    """
    console.print()

    tpm = Path.home() / ".tmux" / "plugins" / "tpm"
    _status_line("tmux plugin manager (tpm)", tpm.exists())
    for plugin in SETUP.get("tmux", {}).get("plugins", []):
        plugin_dir = Path.home() / ".tmux" / "plugins" / plugin.split("/")[-1]
        _status_line(f"  tmux: {plugin}", plugin_dir.exists())

    if shutil.which("fish"):
        _status_line("oh-my-fish", (Path.home() / ".local" / "share" / "omf").exists())
        fisher_ok = subprocess.run(["fish", "-c", "type -q fisher"], capture_output=True).returncode == 0
        _status_line("fisher", fisher_ok)
        if fisher_ok:
            installed = set(_fisher_list())
            for plugin in SETUP.get("fish", {}).get("plugins", []):
                _status_line(f"  fish: {plugin}", plugin in installed)
    else:
        console.print("  [dim]fish not installed — skipping fish tooling check[/dim]")

    console.print()

def _status_line(label: str, ok: bool) -> None:
    """Print a single ✓ / ✗ status line."""
    icon = "[green]✓[/green]" if ok else "[red]✗[/red]"
    console.print(f"  {icon}  {label}")

# ── diff command ──────────────────────────────────────────────────────────────

def cmd_diff(paths: list[str]) -> None:
    """
    Show diffs for every drifted file, or only for the given paths
    (anything under $HOME or /etc, or overlay-relative like .zshrc).
    """
    scopes = all_scopes()
    wanted = set()
    for p in paths:
        full = Path(p).expanduser().absolute()
        # Existing paths are located by where they are (overlay roots first,
        # since the overlay lives under $HOME); anything else is overlay-relative
        roots = [s.repo for s in scopes] + [s.live for s in scopes]
        root = next((r for r in roots if full.exists() and full.is_relative_to(r)), None)
        wanted.add(full.relative_to(root).as_posix() if root else p.removeprefix("./"))

    state = _load_state()
    shown = 0
    for scope in all_scopes():
        for e in scan(scope, state):
            if e.kind in ("same", "blocked"):
                continue
            if wanted and not any(e.rel == w or e.rel.startswith(w.rstrip("/") + "/") for w in wanted):
                continue
            icon, label = KIND_LABEL[e.kind]
            console.rule(f"{icon} [bold]{scope.display(e.rel)}[/bold]  [dim]{label}[/dim]",
                         style="bright_black", align="left")
            if e.live is None:
                console.print("  [dim]Not on this machine yet — apply will create it.[/dim]\n")
            else:
                show_diff(scope, e)
            shown += 1
    _save_state(state)
    if not shown:
        console.print("  [green]✓[/green]  No differences")

# ── add command ───────────────────────────────────────────────────────────────

def cmd_add(path_strs: list[str]) -> None:
    """
    Start tracking files by copying them into the dotfile overlay.
    Directories are added recursively. Paths must be under $HOME; their
    location relative to $HOME is preserved in the overlay, and they are
    recorded as in sync so the next run doesn't flag them.

    Example:
        python3 bootstrap.py add ~/.config/starship.toml ~/.config/ghostty
        → copies to home/benk/.config/...
        → `git add` and commit to make it permanent
    """
    scope = home_scope()
    state = _load_state()
    base = state.setdefault("home", {})
    added: list[Path] = []

    for path_str in path_strs:
        root = Path(path_str).expanduser().absolute()
        if not root.exists() and not root.is_symlink():
            console.print(f"[red]Not found:[/red] {root}")
            continue
        if not root.is_relative_to(Path.home()):
            console.print(f"[red]Not under $HOME:[/red] {root}")
            continue
        files = [root] if not root.is_dir() or root.is_symlink() else \
                [p for p in sorted(root.rglob("*")) if not p.is_dir() or p.is_symlink()]
        for path in files:
            rel = path.relative_to(Path.home()).as_posix()
            dst = scope.repo / rel
            if path.name in JUNK_NAMES or JUNK_DIRS.intersection(rel.split("/")):
                continue
            if dst.exists() and INTERACTIVE:
                if not questionary.confirm(f"  Already tracked: {rel} — overwrite the repo copy?",
                                           default=False).ask():
                    continue
            data = _read(path) or b""
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.is_symlink():
                dst.unlink()
            if path.is_symlink():
                os.symlink(os.readlink(path), dst)
            else:
                shutil.copy2(path, dst)
            base[rel] = _blob_hash(data)
            added.append(dst)
            console.print(f"  [green]✓[/green]  Tracked: [cyan]~/{rel}[/cyan]")

    _save_state(state)
    if added:
        rels = " ".join(str(p.relative_to(DOTFILES_DIR)) for p in added[:3])
        more = " ..." if len(added) > 3 else ""
        console.print(f"  [dim]Commit:  git add {rels}{more} && git commit[/dim]")

# ── stage runner ──────────────────────────────────────────────────────────────
# A Stage is a named, describable unit of work within a mode.
# run_stages() shows a checkbox so the user can skip stages they don't need,
# then runs each selected stage with a clear progress header.

@dataclass
class Stage:
    """A discrete unit of work within a mode (e.g. 'Install packages')."""
    key:   str                 # unique identifier used for checkbox selection
    title: str                 # short display name shown in the checkbox and header
    desc:  str                 # one-line description shown alongside the title
    fn:    Callable[[], None]  # the function to call when this stage runs
    default: bool = True       # pre-checked in the checkbox

# Set once at import time: True if a CLI argument was passed (non-interactive mode).
# run_stages() skips the checkbox and runs all default stages when this is True.
NON_INTERACTIVE = len(sys.argv) > 1 or not INTERACTIVE

def run_stages(mode_title: str, mode_desc: str, stages: list[Stage]) -> None:
    """
    Display a mode panel, let the user select which stages to run via checkbox,
    then execute each selected stage with a numbered progress header.
    Single-stage modes skip the checkbox — there's nothing to choose.
    """
    console.print(Panel(
        f"[bold]{mode_title}[/bold]\n[dim]{mode_desc}[/dim]",
        border_style="bright_blue", padding=(0, 1),
    ))

    if NON_INTERACTIVE or len(stages) == 1:
        to_run = [s for s in stages if s.default]
    else:
        console.print()
        selected_keys = questionary.checkbox(
            "Select which stages to run",
            instruction="(space to toggle, enter to confirm)",
            choices=[_choice(s.title, s.desc, s.key, checked=s.default) for s in stages],
        ).ask()
        if selected_keys is None:
            # questionary returns None on Ctrl-C
            raise KeyboardInterrupt
        if not selected_keys:
            console.print("[yellow]No stages selected — nothing to do.[/yellow]")
            return
        to_run = [s for s in stages if s.key in selected_keys]

    total = len(to_run)
    for i, stage in enumerate(to_run, 1):
        console.print()
        console.rule(
            f"[bold bright_blue]{i}/{total}[/bold bright_blue]"
            f"  [bold]{stage.title}[/bold]  [dim]{stage.desc}[/dim]",
            style="bright_blue", align="left",
        )
        console.print()
        stage.fn()

    console.print()
    console.rule("[bold green]Done[/bold green]", style="green")
    console.print()

# ── modes ─────────────────────────────────────────────────────────────────────
# Each mode is a curated list of stages suited to a particular intent.
# Modes are presented in the TUI select and can also be called from the CLI.

def _sync_stage(direction: str) -> Callable[[], None]:
    """A stage that syncs every scope in one direction and offers a commit."""
    def run() -> None:
        create_home_dirs()
        written: list[str] = []
        for scope in all_scopes():
            written += sync_scope(scope, direction)
        _offer_commit(written)
    return run

def _etc_note() -> str:
    return " + /etc" if etc_scope() else ""

def mode_sync() -> None:
    """
    Day-to-day mode: fast-forward the repo, then move every change that can
    move safely in whichever direction it needs to go, and ask about conflicts.
    """
    run_stages(
        "Sync",
        f"Pull the repo, then sync ~{_etc_note()} both ways",
        [
            Stage("update", "Update repo", "git pull --ff-only", update_repo),
            Stage("sync", "Sync dotfiles", "repo ⇄ machine", _sync_stage("both")),
        ],
    )

def mode_install() -> None:
    """
    Full machine setup: packages → dotfiles → tooling.
    Intended for bootstrapping a new machine from scratch.
    All stages are shown in the checkbox; deselect any you want to skip.
    """
    pkg_mgr = {"macos": "brew", "arch": "yay"}.get(OS, "unknown")
    run_stages(
        "Set up this machine",
        "Install packages, deploy dotfiles, then shell tooling",
        [
            Stage("packages", "Install packages", f"missing ones, via {pkg_mgr}", install_packages),
            Stage("dotfiles", "Deploy dotfiles", f"repo → ~{_etc_note()}", _sync_stage("apply")),
            Stage("tooling",  "Shell tooling",   "tmux tpm · fish plugins", setup_shell_tooling),
        ],
    )

def mode_apply() -> None:
    """Repo → machine only. Local edits are left untouched and reported."""
    run_stages(
        "Apply dotfiles",
        f"Deploy repo changes to ~{_etc_note()} (local edits are kept)",
        [Stage("apply", "Apply dotfiles", "repo → machine", _sync_stage("apply"))],
    )

def mode_save() -> None:
    """
    Machine → repo only. Only files already tracked are saved; use `add` to
    track new ones.
    """
    run_stages(
        "Save changes",
        "Save edits made on this machine into the repo",
        [Stage("save", "Save dotfiles", "machine → repo", _sync_stage("save"))],
    )

# ── mode registry ─────────────────────────────────────────────────────────────
# Modes are keyed by their CLI name. Each entry is (display_title, description, fn).
# The TUI select and the CLI dispatcher both read from this dict,
# so adding a new mode here is the only change needed.

MODES: dict[str, tuple[str, str, Callable[[], None]]] = {
    "sync": (
        "Sync",
        "git pull, then sync changes both ways — the everyday option",
        mode_sync,
    ),
    "status": (
        "Check status",
        "see what differs between this machine and the repo",
        cmd_status,
    ),
    "diff": (
        "Show diffs",
        "see exactly what differs, file by file",
        lambda: cmd_diff([]),
    ),
    "apply": (
        "Apply dotfiles",
        "repo → machine only",
        mode_apply,
    ),
    "save": (
        "Save changes",
        "machine → repo only",
        mode_save,
    ),
    "install": (
        "Set up this machine",
        "install packages, deploy dotfiles, set up shell tooling",
        mode_install,
    ),
}

# Old command names, kept so muscle memory still works
ALIASES = {"copy": "apply", "pull": "save"}

# ── entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    """
    Parse CLI arguments or show the interactive TUI.

    CLI usage (skips the stage checkbox; conflicts are still asked about
    when run from a terminal):
      bootstrap.py sync | install | apply | save | status
      bootstrap.py diff [path...]
      bootstrap.py add <path...>

    Interactive usage (no arguments):
      Shows a mode-select menu, then a stage-select checkbox.
    """
    console.print(Panel(
        Text.assemble(
            ("dotfiles", "bold cyan"), "\n",
            ("  repo  ", "dim"), str(DOTFILES_DIR), "\n",
            ("  user  ", "dim"), USERNAME, "\n",
            ("  os    ", "dim"), OS,
        ),
        border_style="bright_blue",
        padding=(0, 1),
    ))
    console.print()

    args = sys.argv[1:]
    if args:
        cmd = ALIASES.get(args[0].lstrip("-"), args[0].lstrip("-"))
        if cmd == "add":
            if len(args) < 2:
                console.print(
                    "[red]Usage:[/red] bootstrap.py add [cyan]<path...>[/cyan]\n"
                    "  Example: bootstrap.py add ~/.config/starship.toml"
                )
                sys.exit(1)
            cmd_add(args[1:])
        elif cmd == "diff":
            cmd_diff(args[1:])
        elif cmd in MODES:
            MODES[cmd][2]()
        else:
            console.print(
                f"[red]Unknown command:[/red] {args[0]}\n"
                f"  Valid commands: {' | '.join(MODES)} | add <path...>"
            )
            sys.exit(1)
        return

    if not INTERACTIVE:
        console.print("[red]No command given and stdin isn't a terminal.[/red] "
                      f"Valid commands: {' | '.join(MODES)} | add <path...>")
        sys.exit(1)

    choice = questionary.select(
        "What would you like to do?",
        choices=[_choice(title, desc, key) for key, (title, desc, _) in MODES.items()],
    ).ask()
    if choice is None:
        raise KeyboardInterrupt
    MODES[choice][2]()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.print("\n[yellow]Cancelled.[/yellow]")
        sys.exit(130)
