#!/usr/bin/env python3
"""
dot.py — dotfiles manager. Run it through the `dot` launcher.

THE MODEL: two variables, treated differently
---------------------------------------------
  TRUST is a ladder.  profiles.toml lists levels lowest → highest
                      (e.g. common < personal). A machine's profile names the
                      highest level it is trusted with; it gets every level
                      up to and including that one.
  OS is a filter.     macos → [macos], arch → [linux, arch], linux → [linux].

A LAYER is a directory named `<level>` or `<level>@<os>`. A machine applies,
for each level it is trusted with, `<level>` then `<level>@<os>`:

    work Mac       common, common@macos
    personal Mac   common, common@macos, personal, personal@macos
    Arch PC        common, common@linux, common@arch,
                   personal, personal@linux, personal@arch

Later layers win when two layers hold the same path, so an OS layer can
override a generic file, and higher trust wins ties. Only layers that exist
as directories matter. Anything in a layer this machine doesn't apply is
invisible to it — new files fail closed.

Two overlays use these layers:

    home/<layer>/…   mirrors $HOME
    etc/<layer>/…    mirrors /etc   (Linux only, written with sudo)

packages/ is flat (brew.txt, brew-casks.txt, arch.txt): it only exists to set
up a new machine, so it is split by OS and nothing else.

HOW SYNC DECIDES WHO IS NEWER
-----------------------------
Not by timestamps (git stamps everything "now"). Every file is compared by
content, three ways — repo, live, and base (the content both agreed on at the
last sync here, in ~/.local/state/dotfiles/state.json):

  live == repo       in sync
  live missing       new          → deploy
  live == base       repo changed → deploy
  repo == base       live changed → save into the repo
  neither            conflict     → you choose (diff / repo / local / nvim -d)

With no base (first run), a live file matching ANY version in the file's git
history counts as "repo is newer"; anything else is a conflict. Conflicts are
never resolved silently; non-interactive runs skip and list them. Everything
overwritten is backed up to ~/dotfiles.bak/<timestamp>/.

USAGE
-----
  dot                      interactive menu
  dot sync                 git pull, then sync both ways
  dot status               what differs; changes nothing
  dot diff [path...]       exact differences
  dot apply | save         repo → machine | machine → repo   (copy | pull)
  dot install              packages → dotfiles → shell tooling
  dot profile [name]       show / choose this machine's trust level
  dot add [--to LAYER] path...   start tracking files
  dot move path LAYER      move tracked files between layers (promote/demote)
  ~/.dotignore             per-machine exclusions (gitignore-style)
"""
from __future__ import annotations

import difflib, fnmatch, hashlib, json, os, platform, shutil, socket, subprocess, sys, termios, time, tty
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

try:
    import tomllib
except ImportError:                       # Python < 3.11
    import tomli as tomllib               # type: ignore
try:
    import questionary
    from rich.console import Console
    from rich.markup import escape
    from rich.syntax import Syntax
except ImportError:
    sys.exit("dot.py needs rich + questionary — run it through the `dot` launcher.")

console = Console()

# ── paths ─────────────────────────────────────────────────────────────────────
DOTFILES_DIR = Path(__file__).parent.resolve()
HOME         = Path.home()
RUN_STAMP    = time.strftime("%Y%m%d-%H%M%S")
BACKUP_DIR   = HOME / "dotfiles.bak" / RUN_STAMP        # one folder per run
_xdg_state   = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state"))
_xdg_config  = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
STATE_FILE   = _xdg_state / "dotfiles" / "state.json"
MACHINE_FILE = DOTFILES_DIR / ".machine"            # gitignored: what kind of machine this is
_LEGACY_PROFILE = _xdg_config / "dotfiles" / "profile"  # older versions kept it here
INTERACTIVE  = sys.stdin.isatty()

JUNK_NAMES = {".DS_Store", ".gitkeep"}
JUNK_DIRS  = {"__pycache__"}

# ── OS ────────────────────────────────────────────────────────────────────────
def detect_os() -> str:
    if platform.system() == "Darwin":
        return "macos"
    if Path("/etc/arch-release").exists():
        return "arch"
    if Path("/etc/os-release").exists():
        return "linux"
    return "unknown"

OS      = detect_os()
IS_LINUX = OS in ("arch", "linux")
# Generic → specific; every tag becomes a possible `<level>@<tag>` layer
OS_TAGS = {"macos": ["macos"], "arch": ["linux", "arch"], "linux": ["linux"]}.get(OS, [])
ALL_OS_TAGS = ["macos", "linux", "arch"]

# ── trust profiles & layers ───────────────────────────────────────────────────
def _load_profiles() -> tuple[list[str], dict[str, dict]]:
    p = DOTFILES_DIR / "profiles.toml"
    if not p.exists():
        return ["common"], {"personal": {"trust": "common", "desc": "everything"}}
    with open(p, "rb") as f:
        data = tomllib.load(f)
    return data.get("ladder", ["common"]), data.get("profiles", {})

LADDER, PROFILES = _load_profiles()
VALID_LAYERS = {lvl for lvl in LADDER} | {f"{lvl}@{t}" for lvl in LADDER for t in ALL_OS_TAGS}

def saved_profile() -> str | None:
    """This machine's profile ($DOTFILES_PROFILE overrides the saved one)."""
    name = os.environ.get("DOTFILES_PROFILE")
    if not name and MACHINE_FILE.exists():
        name = MACHINE_FILE.read_text().strip()
    if not name and _LEGACY_PROFILE.exists():          # migrate the old location
        name = _LEGACY_PROFILE.read_text().strip()
        if name in PROFILES:
            MACHINE_FILE.write_text(name + "\n")
    return name if name in PROFILES else None

PROFILE_NAME = saved_profile()

def layers_for(profile: str | None) -> list[str]:
    """Ordered layer names a machine with this profile applies (see docstring)."""
    if profile not in PROFILES:
        return []
    trust = PROFILES[profile]["trust"]
    out: list[str] = []
    for lvl in LADDER[: LADDER.index(trust) + 1]:
        out += [lvl] + [f"{lvl}@{t}" for t in OS_TAGS]
    return out

def set_profile(name: str) -> None:
    global PROFILE_NAME
    MACHINE_FILE.write_text(name + "\n")
    PROFILE_NAME = name
    _scopes.clear()

def _choice(title: str, desc: str, value: str, *, checked: bool = False) -> questionary.Choice:
    # questionary renders prompt_toolkit formatted text, not rich markup
    return questionary.Choice(
        title=[("", title), ("fg:ansibrightblack", f"  {desc}")], value=value, checked=checked,
    )

def choose_profile() -> str:
    console.print("[bold]How much should this machine get?[/bold]  "
                  "[dim](change later with `dot profile`)[/dim]\n")
    name = questionary.select(
        "Trust level",
        choices=[_choice(n, c.get("desc", ""), n) for n, c in PROFILES.items()],
    ).ask()
    if name is None:
        raise KeyboardInterrupt
    set_profile(name)
    return name

def cmd_profile(args: list[str]) -> None:
    """`profile` asks (or shows, non-interactively); `profile <name>` switches."""
    if args:
        if args[0] not in PROFILES:
            console.print(f"[red]Unknown profile:[/red] {args[0]}  (have: {', '.join(PROFILES)})")
            sys.exit(1)
        set_profile(args[0])
    elif INTERACTIVE:
        choose_profile()
    console.print(f"  profile  [bold cyan]{PROFILE_NAME or 'none'}[/bold cyan]"
                  f"  [dim]{PROFILES.get(PROFILE_NAME or '', {}).get('desc', '')}[/dim]")
    console.print(f"  layers   [dim]{', '.join(layers_for(PROFILE_NAME)) or '-'}[/dim]")
    console.print("  [dim]Switching never deletes files — it only changes what is synced.[/dim]")

# ── scopes: one overlay root ⇄ one live root ──────────────────────────────────
def _load_dotignore() -> list[str]:
    p = HOME / ".dotignore"
    if not p.exists():
        return []
    return [ln.strip() for ln in p.read_text().splitlines()
            if ln.strip() and not ln.strip().startswith("#")]

def _ignored(rel: str, patterns: list[str]) -> bool:
    """
    gitignore-style match of a path against patterns:
      'dir/'          everything under any directory named dir
      'a/b' '/a/b'    contains a slash → anchored at the root
      '*.log'         no slash → matches any single path component
    """
    parts = rel.split("/")
    for raw in patterns:
        pat = raw.strip()
        dir_only = pat.endswith("/")
        pat = pat.strip("/")
        if not pat:
            continue
        n = len(parts) - 1 if dir_only else len(parts)
        if "/" in raw.strip().rstrip("/"):
            if any(fnmatch.fnmatchcase("/".join(parts[:i]), pat) for i in range(1, n + 1)):
                return True
        elif any(fnmatch.fnmatchcase(part, pat) for part in parts[:n]):
            return True
    return False

@dataclass
class Scope:
    name:     str            # 'home' | 'etc' (key in the state file)
    root:     Path           # DOTFILES_DIR/home or /etc — holds the layer dirs
    live:     Path           # $HOME or /etc
    sudo:     bool
    layers:   list[str]      # applied layers, in order
    excludes: list[str]
    _src: dict[str, str] | None = field(default=None, repr=False)

    def display(self, rel: str) -> str:
        return f"~/{rel}" if self.name == "home" else f"/etc/{rel}"

    def sources(self) -> dict[str, str]:
        """rel path → the layer that provides it (later layers win)."""
        if self._src is None:
            src: dict[str, str] = {}
            for layer in self.layers:
                d = self.root / layer
                if not d.is_dir():
                    continue
                for p in sorted(d.rglob("*")):
                    if p.is_dir() and not p.is_symlink():
                        continue
                    rel = p.relative_to(d).as_posix()
                    parts = rel.split("/")
                    if parts[-1] in JUNK_NAMES or JUNK_DIRS.intersection(parts[:-1]):
                        continue
                    if _ignored(rel, self.excludes):
                        continue
                    src[rel] = layer
            self._src = src
        return self._src

    def refresh(self) -> None:
        self._src = None

    def src(self, rel: str) -> Path:
        """The repo file that provides `rel`."""
        return self.root / self.sources()[rel] / rel

    def layer_of(self, rel: str) -> str:
        return self.sources()[rel]

    def tracked(self) -> list[str]:
        return sorted(self.sources())

    def unknown_dirs(self) -> list[str]:
        """Directories under the root that aren't valid layer names (typos fail closed)."""
        if not self.root.is_dir():
            return []
        return sorted(d.name for d in self.root.iterdir()
                      if d.is_dir() and d.name not in VALID_LAYERS)

_scopes: dict[str, Scope | None] = {}

def home_scope() -> Scope:
    if "home" not in _scopes:
        _scopes["home"] = Scope("home", DOTFILES_DIR / "home", HOME, False,
                                layers_for(PROFILE_NAME), _load_dotignore())
    return _scopes["home"]  # type: ignore

def etc_scope() -> Scope | None:
    """/etc overlay. Linux only: these files describe Linux machines."""
    if "etc" not in _scopes:
        root = DOTFILES_DIR / "etc"
        s = Scope("etc", root, Path("/etc"), True, layers_for(PROFILE_NAME), ["*.md"])
        _scopes["etc"] = s if IS_LINUX and root.is_dir() and s.tracked() else None
    return _scopes["etc"]

def all_scopes() -> list[Scope]:
    return [s for s in (home_scope(), etc_scope()) if s]

# ── content hashing ───────────────────────────────────────────────────────────
# Git's blob hash, so a live file's hash can be looked up in the repo's history.
# Symlinks hash their target path, exactly what git stores.

def _blob_hash(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()

def _read(path: Path, *, sudo: bool = False) -> bytes | None:
    """Content (or symlink target); None if absent; IsADirectoryError for dirs."""
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
        return subprocess.run(["sudo", "cat", str(path)], check=True, capture_output=True).stdout

_history_cache: dict[str, dict[str, set[str]]] = {}

def _rel_from_repo_path(scope: Scope, path: str) -> str:
    """
    'home/personal@linux/.config/x' → '.config/x'. Also understands the old
    layouts (home/benk/…, etc/fstab) so history survives the move into layers.
    """
    parts = path.split("/")[1:]
    if scope.name == "home":
        return "/".join(parts[1:])
    if parts and parts[0] in VALID_LAYERS | {"benk"}:
        parts = parts[1:]
    return "/".join(parts)

def _git_history(scope: Scope) -> dict[str, set[str]]:
    """live-relative path → every blob hash it ever had, across all layers."""
    if scope.name in _history_cache:
        return _history_cache[scope.name]
    history: dict[str, set[str]] = {}
    try:
        out = subprocess.run(
            ["git", "-c", "core.quotePath=off", "log", "--format=", "--raw", "--no-abbrev",
             "--no-renames", "--", scope.root.relative_to(DOTFILES_DIR).as_posix()],
            cwd=DOTFILES_DIR, capture_output=True, text=True, timeout=60,
        ).stdout
        for line in out.splitlines():
            if not line.startswith(":") or "\t" not in line:
                continue
            meta, path = line.split("\t", 1)
            history.setdefault(_rel_from_repo_path(scope, path), set()).update(meta.split()[2:4])
    except (OSError, subprocess.TimeoutExpired, ValueError):
        pass
    for blobs in history.values():
        blobs.discard("0" * 40)
    _history_cache[scope.name] = history
    return history

# ── sync state ────────────────────────────────────────────────────────────────
def _load_state() -> dict[str, dict[str, str]]:
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        return {}

def _save_state(state: dict[str, dict[str, str]]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1, sort_keys=True))
    tmp.replace(STATE_FILE)

# ── classification ────────────────────────────────────────────────────────────
@dataclass
class Entry:
    rel:   str
    kind:  str                 # same | new | repo | local | conflict | blocked
    layer: str = ""
    repo:  bytes = b""
    live:  bytes | None = None
    why:   str = ""

KIND_ORDER = ["new", "repo", "local", "conflict", "blocked"]
KIND_LABEL = {
    "new":      ("[blue]+[/blue]",     "not on this machine yet"),
    "repo":     ("[cyan]↓[/cyan]",     "changed in the repo"),
    "local":    ("[yellow]↑[/yellow]", "changed on this machine"),
    "conflict": ("[red]![/red]",       "need you to choose"),
    "blocked":  ("[red]✗[/red]",       "can't be synced"),
}

def classify(scope: Scope, rel: str, base: dict[str, str]) -> Entry:
    layer = scope.layer_of(rel)
    repo = _read(scope.src(rel)) or b""
    try:
        live = _read(scope.live / rel, sudo=scope.sudo)
    except IsADirectoryError:
        return Entry(rel, "blocked", layer, repo, None, "a directory exists at this path")
    except (PermissionError, subprocess.CalledProcessError) as e:
        return Entry(rel, "blocked", layer, repo, None, f"unreadable: {e}")

    if live is None:
        return Entry(rel, "new", layer, repo, None)
    repo_h, live_h = _blob_hash(repo), _blob_hash(live)
    if repo_h == live_h:
        return Entry(rel, "same", layer, repo, live)
    if rel in base:
        if live_h == base[rel]:
            return Entry(rel, "repo", layer, repo, live)
        if repo_h == base[rel]:
            return Entry(rel, "local", layer, repo, live)
        return Entry(rel, "conflict", layer, repo, live, "both sides changed since the last sync")
    if live_h in _git_history(scope).get(rel, ()):
        return Entry(rel, "repo", layer, repo, live, "this machine has an older committed version")
    return Entry(rel, "conflict", layer, repo, live,
                 "never synced on this machine, so there's no telling which side is newer")

def scan(scope: Scope, state: dict[str, dict[str, str]]) -> list[Entry]:
    """Classify everything tracked; keep the base fresh for files already in sync."""
    base = state.setdefault(scope.name, {})
    rels = scope.tracked()
    entries = [classify(scope, rel, base) for rel in rels]
    for e in entries:
        if e.kind == "same":
            base[e.rel] = _blob_hash(e.repo)
    for rel in set(base) - set(rels):
        del base[rel]
    return entries

# ── file operations ───────────────────────────────────────────────────────────
def _backup(scope: Scope, rel: str, data: bytes, side: str) -> None:
    dst = BACKUP_DIR / side / scope.name / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(data)

def deploy(scope: Scope, e: Entry) -> None:
    """Repo → live, backing up whatever is overwritten."""
    src, dst = scope.src(e.rel), scope.live / e.rel
    if e.live is not None:
        _backup(scope, e.rel, e.live, "machine")
    if scope.sudo:
        subprocess.run(["sudo", "mkdir", "-p", str(dst.parent)], check=True)
        subprocess.run(["sudo", "cp", "-P", "--preserve=mode", "--remove-destination",
                        str(src), str(dst)], check=True)
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.is_symlink():                       # never write through a link
        dst.unlink()
    if src.is_symlink():
        os.symlink(os.readlink(src), dst)
    else:
        shutil.copy2(src, dst)

def capture(scope: Scope, e: Entry) -> None:
    """Live → repo (into the layer that already provides the file)."""
    src, dst = scope.live / e.rel, scope.src(e.rel)
    _backup(scope, e.rel, e.repo, "repo")
    if dst.is_symlink():
        dst.unlink()
    if src.is_symlink():
        os.symlink(os.readlink(src), dst)
    else:
        dst.write_bytes(e.live or b"")
        if not scope.sudo:
            shutil.copymode(src, dst)

def _repo_rel(scope: Scope, rel: str) -> str:
    return scope.src(rel).relative_to(DOTFILES_DIR).as_posix()

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
    """Coloured unified diff, this machine → repo."""
    if _is_binary(e.repo) or _is_binary(e.live):
        console.print(f"  [dim]{e.rel}: binary — this machine {len(e.live or b'')} bytes, "
                      f"repo {len(e.repo)} bytes[/dim]")
        return
    lines = list(difflib.unified_diff(
        (e.live or b"").decode().splitlines(keepends=True),
        e.repo.decode().splitlines(keepends=True),
        fromfile=f"{scope.display(e.rel)}  (this machine)",
        tofile=f"{_repo_rel(scope, e.rel)}  (repo)",
    ))
    text = "".join(ln if ln.endswith("\n") else ln + "\n" for ln in lines)
    syntax = Syntax(text, "diff", theme="ansi_dark", background_color="default")
    if len(lines) > console.height - 4 and INTERACTIVE:
        with console.pager(styles=True):
            console.print(syntax)
    else:
        console.print(syntax)

def _key(valid: str) -> str:
    """Read ONE keypress (no Enter) and return it if it's in `valid`; Ctrl-C cancels."""
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while True:
            ch = sys.stdin.read(1)
            if ch in ("\x03", "\x04"):
                raise KeyboardInterrupt
            if ch.lower() in valid:
                return ch.lower()
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

# ── conflict resolution ───────────────────────────────────────────────────────
_STOP = False        # set when the user picks "stop here" — remaining conflicts are skipped

def resolve(scope: Scope, e: Entry) -> str:
    """
    Show the diff, then one keypress: r repo · l local · m merge · s skip · q stop.
    Returns 'repo' | 'local' | 'merged' | 'skip'.
    """
    global _STOP
    can_merge = not scope.sudo and shutil.which("nvim") and not _is_binary(e.repo)
    while True:
        console.print(f"\n[red]![/red] [bold]{scope.display(e.rel)}[/bold]  "
                      f"[dim]{e.why} · {escape('[' + e.layer + ']')}[/dim]\n")
        show_diff(scope, e)
        legend = ["[bold]r[/bold] use repo version [dim](backed up)[/dim]",
                  "[bold]l[/bold] keep this machine's [dim](saved to repo)[/dim]"]
        if can_merge:
            legend.append("[bold]m[/bold] merge in nvim")
        legend += ["[bold]s[/bold] skip", "[bold]q[/bold] stop"]
        console.print("  " + "   ".join(legend))
        console.print("  [cyan]›[/cyan] ", end="")
        answer = {"r": "repo", "l": "local", "m": "merge", "s": "skip", "q": "stop"}[
            _key("rlmsq" if can_merge else "rlsq")]
        console.print(answer)
        if answer == "stop":
            _STOP = True
            return "skip"
        if answer != "merge":
            return answer
        subprocess.run(["nvim", "-d", str(scope.live / e.rel), str(scope.src(e.rel))])
        e.repo = _read(scope.src(e.rel)) or b""
        e.live = _read(scope.live / e.rel)
        if e.live is not None and _blob_hash(e.live) == _blob_hash(e.repo):
            return "merged"
        console.print("  [yellow]The two versions still differ.[/yellow]")

# ── presentation helpers ──────────────────────────────────────────────────────
VERBOSE = False      # -v: list every file instead of grouping by tool

def _tool(scope: Scope, rel: str) -> str:
    """Friendly group name for a path: .config/nvim/x → nvim, .tmux.conf → tmux."""
    p = rel.split("/")
    if p[0] == ".config" and len(p) > 1:
        name = p[1]
    elif p[:2] == [".local", "share"] and len(p) > 2:
        name = p[2]
    elif p[0] == "Library":
        name = p[-1].replace(".plist", "").split(".")[-1]
    else:
        name = p[0] if len(p) > 1 else p[-1]
    name = name.lstrip(".")
    name = (name.split(".")[0] or name)
    return f"/etc/{name}" if scope.name == "etc" else name

def _groups(items: list[tuple[Scope, Entry]]) -> str:
    """'nvim 5 · fish · zed 2'"""
    counts: dict[str, int] = {}
    for s, e in items:
        t = _tool(s, e.rel)
        counts[t] = counts.get(t, 0) + 1
    return " · ".join(f"{t} {n}" if n > 1 else t for t, n in sorted(counts.items()))

def _file_lines(items: list[tuple[Scope, Entry]], note: Callable[[Entry], str] = lambda e: "") -> None:
    for s, e in items:
        console.print(f"       [dim]{s.display(e.rel)}  {escape('[' + e.layer + ']')}{note(e)}[/dim]")

KIND_NOUN = {"new": "new here", "repo": "updated in repo", "local": "edited here",
             "conflict": "conflict", "blocked": "blocked"}

def _diff_stat(e: Entry) -> str:
    if _is_binary(e.repo) or _is_binary(e.live):
        return "binary"
    old = (e.live or b"").decode().splitlines()
    new = e.repo.decode().splitlines()
    if e.live is None:
        return f"new file, {len(new)} lines"
    plus = minus = 0
    for ln in difflib.unified_diff(old, new, lineterm="", n=0):
        if ln.startswith("+") and not ln.startswith("+++"):
            plus += 1
        elif ln.startswith("-") and not ln.startswith("---"):
            minus += 1
    return f"+{plus} −{minus}"

# ── sync engine ───────────────────────────────────────────────────────────────
def collect() -> list[tuple[Scope, Entry]]:
    """Scan every scope; (scope, entry) for each tracked file, in sync or not."""
    state = _load_state()
    items = [(s, e) for s in all_scopes() for e in scan(s, state)]
    _save_state(state)
    return items

def _report(verb: str, kind: str, group: list[tuple[Scope, Entry]]) -> None:
    icon = KIND_LABEL[kind][0]
    console.print(f"  {icon}  {verb} {len(group)}   [dim]{_groups(group)}[/dim]")
    if VERBOSE:
        _file_lines(group)

def sync_scope(scope: Scope, direction: str, only: set[str] | None = None) -> tuple[list[str], int]:
    """
    direction: 'apply' repo→machine · 'save' machine→repo · 'both'.
    only: if given, just these rel paths move (conflicts are still asked about).
    Returns (repo-relative paths written into the repo, number of files moved).
    """
    state = _load_state()
    entries = scan(scope, state)
    base = state[scope.name]
    by_kind = {k: [e for e in entries if e.kind == k] for k in KIND_ORDER}
    pick = (lambda es: es) if only is None else (lambda es: [e for e in es if e.rel in only])

    to_deploy  = pick(by_kind["new"] + by_kind["repo"]) if direction in ("apply", "both") else []
    to_capture = pick(by_kind["local"]) if direction in ("save", "both") else []
    held_back  = (by_kind["local"] if direction == "apply" else []) + \
                 (by_kind["new"] + by_kind["repo"] if direction == "save" else [])

    global _STOP
    written: list[str] = []
    skipped: list[Entry] = []
    resolved = 0
    try:
        for e in to_deploy:
            deploy(scope, e)
            base[e.rel] = _blob_hash(e.repo)
        for e in to_capture:
            capture(scope, e)
            base[e.rel] = _blob_hash(e.live or b"")
            written.append(_repo_rel(scope, e.rel))
        for e in by_kind["conflict"]:
            if not INTERACTIVE or _STOP:
                skipped.append(e)
                continue
            answer = resolve(scope, e)
            if answer == "repo":
                deploy(scope, e)
                base[e.rel] = _blob_hash(e.repo)
            elif answer == "local":
                capture(scope, e)
                base[e.rel] = _blob_hash(e.live or b"")
                written.append(_repo_rel(scope, e.rel))
            elif answer == "merged":
                base[e.rel] = _blob_hash(e.repo)
                written.append(_repo_rel(scope, e.rel))
            else:
                skipped.append(e)
                continue
            resolved += 1
    finally:
        _save_state(state)           # keep progress even on Ctrl-C mid-conflicts

    pair = lambda es: [(scope, e) for e in es]
    for verb, kind, es in (("created", "new", [e for e in to_deploy if e.kind == "new"]),
                           ("updated", "repo", [e for e in to_deploy if e.kind == "repo"]),
                           ("saved", "local", to_capture)):
        if es:
            _report(verb, kind, pair(es))
    if resolved:
        console.print(f"  [green]✓[/green]  resolved {resolved}")
    if skipped:
        console.print(f"  [red]![/red]  {len(skipped)} conflict(s) left alone   "
                      f"[dim]{_groups(pair(skipped))} — run `dot` to resolve[/dim]")
        if VERBOSE:
            _file_lines(pair(skipped), lambda e: f"  ({e.why})")
    if held_back:
        hint = "`dot save`" if direction == "apply" else "`dot apply`"
        console.print(f"  [dim]·  {len(held_back)} file(s) differ the other way — {hint}[/dim]")
    if by_kind["blocked"]:
        console.print(f"  [red]✗[/red]  {len(by_kind['blocked'])} can't be synced")
        _file_lines(pair(by_kind["blocked"]), lambda e: f"  ({e.why})")
    if any(e.live is not None for e in to_deploy):
        console.print(f"  [dim]·  overwritten files backed up to {BACKUP_DIR}[/dim]")
    return written, len(to_deploy) + len(to_capture) + resolved

def _offer_commit(paths: list[str]) -> None:
    """One question: commit the files that were just saved into the repo?"""
    if not paths:
        return
    host = socket.gethostname().split(".")[0]
    msg = f"sync from {host}"
    if not INTERACTIVE:
        console.print(f"  [dim]{len(paths)} file(s) saved into the repo — commit with git -C ~/dotfiles commit[/dim]")
        return
    if questionary.confirm(f"Commit the {len(paths)} saved file(s) as “{msg}”?", default=True,
                           qmark="").ask():
        subprocess.run(["git", "add", "--", *paths], cwd=DOTFILES_DIR, check=True)
        subprocess.run(["git", "commit", "-q", "-m", msg, "--", *paths], cwd=DOTFILES_DIR)
        console.print("  [green]✓[/green]  committed")

def do_sync(direction: str = "both", only: dict[str, set[str]] | None = None) -> None:
    """Sync every scope, then offer to commit whatever was saved into the repo."""
    create_home_dirs()
    written: list[str] = []
    moved = 0
    for scope in all_scopes():
        w, n = sync_scope(scope, direction, None if only is None else only.get(scope.name, set()))
        written += w
        moved += n
    if not moved:
        console.print("  [green]✓[/green]  already in sync")
    _offer_commit(written)

def update_repo() -> None:
    """Fast-forward the repo (autostash, never merges/rebases)."""
    if subprocess.run(["git", "rev-parse", "--abbrev-ref", "@{upstream}"],
                      cwd=DOTFILES_DIR, capture_output=True).returncode != 0:
        console.print("  [dim]No upstream branch configured — skipping git pull[/dim]")
        return
    try:
        # No controlling terminal + no stdin: ssh/git can't stop to prompt, so a flaky
        # network or an unknown host fails fast instead of hanging the whole UI.
        r = subprocess.run(["git", "pull", "--ff-only", "--autostash", "--recurse-submodules"],
                           cwd=DOTFILES_DIR, capture_output=True, text=True, stdin=subprocess.DEVNULL,
                           start_new_session=True, timeout=60,
                           env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
    except subprocess.TimeoutExpired:
        console.print("  [yellow]![/yellow]  git pull timed out — syncing against the local repo as-is")
        return
    if r.returncode == 0:
        console.print(f"  [green]✓[/green]  "
                      f"{r.stdout.strip().splitlines()[-1] if r.stdout.strip() else 'Up to date'}")
        _history_cache.clear()
        for s in _scopes.values():
            if s:
                s.refresh()
    else:
        console.print("  [yellow]![/yellow]  git pull failed — syncing against the local repo as-is")
        console.print(f"  [dim]{r.stderr.strip()}[/dim]")

def create_home_dirs() -> None:
    for d in [HOME / ".config", HOME / ".local" / "bin", HOME / ".local" / "share",
              HOME / ".local" / "state", HOME / ".ssh"]:
        d.mkdir(parents=True, exist_ok=True)
    (HOME / ".ssh").chmod(0o700)          # ssh refuses anything looser

# ── packages (flat, split by OS only) ─────────────────────────────────────────
def _read_packages(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [ln.strip() for ln in path.read_text().splitlines()
            if ln.strip() and not ln.startswith("#")]

def _missing(wanted: list[str], installed: set[str]) -> list[str]:
    return [p for p in wanted if p.rsplit("/", 1)[-1] not in installed]

def _brew_installed(kind: str) -> set[str]:
    return set(subprocess.check_output(["brew", "list", f"--{kind}", "-1"], text=True).split())

def _install_one(cmd: list[str], pkg: str) -> None:
    """Run `cmd pkg`; on failure ask whether to continue (a half-installed box is worse)."""
    console.print(f"  [dim]{' '.join(cmd)} {pkg}[/dim]")
    r = subprocess.run(cmd + [pkg], capture_output=True, text=True)
    if r.returncode != 0:
        console.print(f"  [red][!] Failed to install:[/red] {pkg}")
        console.print(f"  [dim]{r.stderr.strip()[-500:]}[/dim]")
        if not INTERACTIVE or not questionary.confirm("  Continue anyway?", default=False).ask():
            sys.exit(1)

def install_packages() -> None:
    if OS == "macos":
        _install_brew()
    elif OS == "arch":
        _install_arch()
    else:
        console.print("[yellow]Unknown OS — skipping package install.[/yellow]")

def _install_brew() -> None:
    if not shutil.which("brew"):
        console.print("  [bold]Homebrew not found — installing...[/bold]")
        subprocess.run(["/bin/bash", "-c",
                        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"],
                       check=True)
    for kind, file, cmd in [("formula", "brew.txt", ["brew", "install"]),
                            ("cask", "brew-casks.txt", ["brew", "install", "--cask"])]:
        wanted = _read_packages(DOTFILES_DIR / "packages" / file)
        missing = _missing(wanted, _brew_installed(kind))
        console.print(f"  [green]✓[/green]  {len(wanted) - len(missing)}/{len(wanted)} {kind}s already installed")
        for pkg in missing:
            _install_one(cmd, pkg)

def _install_arch() -> None:
    if not shutil.which("yay"):
        console.print("  [bold]yay not found — bootstrapping from AUR...[/bold]")
        subprocess.run(["sudo", "pacman", "-S", "--needed", "--noconfirm", "git", "base-devel"], check=True)
        tmp = Path(subprocess.check_output(["mktemp", "-d"]).decode().strip())
        subprocess.run(["git", "clone", "https://aur.archlinux.org/yay.git", str(tmp / "yay")], check=True)
        subprocess.run(["makepkg", "-si", "--noconfirm"], cwd=tmp / "yay", check=True)
        shutil.rmtree(tmp)
    wanted = _read_packages(DOTFILES_DIR / "packages" / "arch.txt")
    missing = _missing(wanted, set(subprocess.check_output(["pacman", "-Qq"], text=True).split()))
    console.print(f"  [green]✓[/green]  {len(wanted) - len(missing)}/{len(wanted)} packages already installed")
    for pkg in missing:
        _install_one(["yay", "-S", "--needed", "--noconfirm"], pkg)

# ── shell tooling (setup.toml) ────────────────────────────────────────────────
def _load_setup() -> dict:
    p = DOTFILES_DIR / "setup.toml"
    if not p.exists():
        return {}
    with open(p, "rb") as f:
        return tomllib.load(f)

SETUP = _load_setup()

def setup_shell_tooling() -> None:
    _setup_tmux()
    _setup_fish()

def _setup_tmux() -> None:
    tpm = HOME / ".tmux" / "plugins" / "tpm"
    if not tpm.exists():
        console.print("  Installing tmux plugin manager (tpm)...")
        subprocess.run(["git", "clone", "https://github.com/tmux-plugins/tpm", str(tpm)], check=True)
    else:
        console.print("  [green]✓[/green]  tmux plugin manager")
    script = tpm / "bin" / "install_plugins"
    if script.exists():
        subprocess.run([str(script)], capture_output=True)
        console.print("  [green]✓[/green]  tmux plugins")
    else:
        console.print("  [yellow]![/yellow]  Run [dim]<prefix>I[/dim] inside tmux to install plugins")

def _fisher_list() -> list[str]:
    return subprocess.run(["fish", "-c", "fisher list"], capture_output=True, text=True).stdout.split()

def _setup_fish() -> None:
    if not shutil.which("fish"):
        console.print("  [dim]fish not installed — skipping fish setup[/dim]")
        return
    if not (HOME / ".local" / "share" / "omf").exists():
        console.print("  Installing oh-my-fish...")
        subprocess.run(["fish", "-c", "curl -L https://get.oh-my.fish > /tmp/omf-install; "
                                      "fish /tmp/omf-install --noninteractive --yes"], check=True)
    else:
        console.print("  [green]✓[/green]  oh-my-fish")
    if subprocess.run(["fish", "-c", "type -q fisher"], capture_output=True).returncode != 0:
        console.print("  Installing fisher...")
        subprocess.run(["fish", "-c", "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/"
                                      "functions/fisher.fish | source && fisher install jorgebucaran/fisher"],
                       check=True)
    else:
        console.print("  [green]✓[/green]  fisher")
    if (HOME / ".config" / "fish" / "fish_plugins").exists():
        subprocess.run(["fish", "-c", "fisher update"], capture_output=True)
    plugins = SETUP.get("fish", {}).get("plugins", [])
    todo = [p for p in plugins if p not in set(_fisher_list())] if plugins else []
    if todo:
        console.print(f"  Installing {len(todo)} fish plugin(s)...")
        subprocess.run(["fish", "-c", f"fisher install {' '.join(todo)}"], check=True)
    console.print("  [green]✓[/green]  fish plugins")

# ── status ────────────────────────────────────────────────────────────────────
def _status_line(label: str, ok: bool) -> None:
    console.print(f"  [{'green' if ok else 'red'}]{'✓' if ok else '✗'}[/]  {label}")

def _status_pkg_list(label: str, wanted: list[str], installed: set[str]) -> None:
    missing = _missing(wanted, installed)
    for p in missing:
        console.print(f"  [red]✗[/red]  {p}  [dim]({label} — not installed)[/dim]")
    console.print(f"  [green]✓[/green]  {len(wanted) - len(missing)}/{len(wanted)} {label} installed")

def _status_packages() -> None:
    console.print()
    if OS == "macos":
        if not shutil.which("brew"):
            console.print("  [red]✗[/red]  Homebrew is not installed\n")
            return
        _status_pkg_list("formulae", _read_packages(DOTFILES_DIR / "packages" / "brew.txt"),
                         _brew_installed("formula"))
        _status_pkg_list("casks", _read_packages(DOTFILES_DIR / "packages" / "brew-casks.txt"),
                         _brew_installed("cask"))
    elif IS_LINUX and shutil.which("pacman"):
        _status_pkg_list("packages", _read_packages(DOTFILES_DIR / "packages" / "arch.txt"),
                         set(subprocess.check_output(["pacman", "-Qq"], text=True).split()))
    else:
        console.print("  [dim]Package status not supported on this OS[/dim]")
    console.print()

def _status_tooling() -> None:
    console.print()
    _status_line("tmux plugin manager (tpm)", (HOME / ".tmux" / "plugins" / "tpm").exists())
    for plugin in SETUP.get("tmux", {}).get("plugins", []):
        _status_line(f"  tmux: {plugin}", (HOME / ".tmux" / "plugins" / plugin.split("/")[-1]).exists())
    if shutil.which("fish"):
        _status_line("oh-my-fish", (HOME / ".local" / "share" / "omf").exists())
        ok = subprocess.run(["fish", "-c", "type -q fisher"], capture_output=True).returncode == 0
        _status_line("fisher", ok)
        if ok:
            have = set(_fisher_list())
            for plugin in SETUP.get("fish", {}).get("plugins", []):
                _status_line(f"  fish: {plugin}", plugin in have)
    else:
        console.print("  [dim]fish not installed — skipping fish tooling check[/dim]")

def _repo_brief() -> str:
    """'✓ clean · up to date' / '● 3 uncommitted · 2 to pull'"""
    dirty = subprocess.run(["git", "status", "--porcelain"], cwd=DOTFILES_DIR,
                           capture_output=True, text=True).stdout.splitlines()
    bits = [f"[yellow]● {len(dirty)} uncommitted[/yellow]" if dirty else "[green]✓[/green] clean"]
    c = subprocess.run(["git", "rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
                       cwd=DOTFILES_DIR, capture_output=True, text=True)
    if c.returncode == 0:
        behind, ahead = (int(n) for n in c.stdout.split())
        if behind:
            bits.append(f"[cyan]{behind} to pull[/cyan]")
        if ahead:
            bits.append(f"[cyan]{ahead} to push[/cyan]")
        if not behind and not ahead:
            bits.append("up to date")
    return " · ".join(bits)

def dashboard(items: list[tuple[Scope, Entry]]) -> None:
    """The at-a-glance view: where you are, and what would move."""
    console.print(f"[bold cyan]dot[/bold cyan]  [dim]{OS} · {PROFILE_NAME}  "
                  f"{escape('[' + ', '.join(layers_for(PROFILE_NAME)) + ']')}[/dim]")
    console.print(f"[dim]repo[/dim]  {_repo_brief()}\n")
    drift = [(s, e) for s, e in items if e.kind != "same"]
    if not drift:
        console.print(f"  [green]✓[/green]  in sync  [dim]{len(items)} files[/dim]")
    for kind in KIND_ORDER:
        g = [(s, e) for s, e in drift if e.kind == kind]
        if g:
            console.print(f"  {KIND_LABEL[kind][0]}  {len(g):>3} {KIND_NOUN[kind]:<16}"
                          f" [dim]{_groups(g)}[/dim]")
            if VERBOSE or kind in ("conflict", "blocked"):
                _file_lines(g, lambda e: f"  ({e.why})" if e.why and e.kind in ("conflict", "blocked") else "")
    for s in all_scopes():
        if s.unknown_dirs():
            console.print(f"\n  [yellow]![/yellow]  ignoring unknown layer dir(s) in {s.root.name}/: "
                          f"{', '.join(s.unknown_dirs())}  [dim](valid: <level> or <level>@<os>)[/dim]")
    console.print()

def cmd_status(everything: bool = False) -> None:
    """Dashboard with every drifted file listed. --all adds packages and tooling."""
    global VERBOSE
    VERBOSE = True
    dashboard(collect())
    if everything:
        console.print("[bold]packages[/bold]")
        _status_packages()
        console.print("[bold]tooling[/bold]")
        _status_tooling()

# ── path helpers for diff / add / move ────────────────────────────────────────
def _locate(path_str: str) -> tuple[Scope, str] | None:
    """Map a path under $HOME or /etc (or overlay-relative → home) to (scope, rel)."""
    if not path_str.startswith(("/", "~", "./", "../")):
        # bare relative path (.tmux.conf, .config/nvim): a tracked overlay path wins
        rel = path_str.rstrip("/")
        for scope in all_scopes():
            if any(r == rel or r.startswith(rel + "/") for r in scope.tracked()):
                return scope, rel
    full = Path(path_str).expanduser().absolute()
    for scope in all_scopes():
        if full.is_relative_to(scope.live) and full != scope.live:
            return scope, full.relative_to(scope.live).as_posix()
    return None

def cmd_diff(paths: list[str]) -> None:
    """Show diffs for every drifted file, or only those under the given paths."""
    wanted: dict[str, set[str]] = {}
    for p in paths:
        loc = _locate(p)
        if loc:
            wanted.setdefault(loc[0].name, set()).add(loc[1])
        else:                                      # overlay-relative, e.g. .zshrc
            wanted.setdefault("home", set()).add(p.removeprefix("./"))
    state = _load_state()
    shown = 0
    for scope in all_scopes():
        for e in scan(scope, state):
            if e.kind in ("same", "blocked"):
                continue
            w = wanted.get(scope.name, set())
            if paths and not any(e.rel == x or e.rel.startswith(x.rstrip("/") + "/") for x in w):
                continue
            icon, label = KIND_LABEL[e.kind]
            console.print(f"\n{icon} [bold]{scope.display(e.rel)}[/bold]  [dim]{label} · {escape('[' + e.layer + ']')}[/dim]")
            if e.live is None:
                console.print("  [dim]Not on this machine yet — apply will create it.[/dim]\n")
            else:
                show_diff(scope, e)
            shown += 1
    _save_state(state)
    if not shown:
        console.print("  [green]✓[/green]  No differences")

def _default_layer(scope: Scope) -> str:
    """Where new files go by default: the HIGHEST-trust generic layer (fail closed)."""
    return next(l for l in reversed(scope.layers) if "@" not in l)

def _pick_layer(scope: Scope, requested: str | None, what: str) -> str | None:
    if requested:
        if requested not in scope.layers:
            console.print(f"[red]Layer '{requested}' doesn't apply on this machine.[/red] "
                          f"Available: {', '.join(scope.layers)}")
            return None
        return requested
    if not INTERACTIVE:
        return _default_layer(scope)
    layer = questionary.select(
        f"Which layer should {what} go in?",
        choices=[_choice(l, "everywhere" if "@" not in l else f"only on {l.split('@')[1]}", l)
                 for l in scope.layers],
        default=_default_layer(scope),
    ).ask()
    if layer is None:
        raise KeyboardInterrupt
    return layer

def cmd_add(path_strs: list[str], layer: str | None = None) -> None:
    """
    Start tracking files (directories recursively) by copying them into a layer.
    A file already tracked stays in its current layer unless --to is given.
    """
    state = _load_state()
    added: list[Path] = []
    chosen: dict[str, str] = {}
    for path_str in path_strs:
        root = Path(path_str).expanduser().absolute()
        loc = _locate(path_str)
        if not root.exists() and not root.is_symlink():
            console.print(f"[red]Not found:[/red] {root}")
            continue
        if not loc:
            console.print(f"[red]Not under $HOME{' or /etc' if IS_LINUX else ''}:[/red] {root}")
            continue
        scope = loc[0]
        files = [root] if not root.is_dir() or root.is_symlink() else \
                [p for p in sorted(root.rglob("*")) if not p.is_dir() or p.is_symlink()]
        if scope.name not in chosen:
            target = _pick_layer(scope, layer, path_str)
            if target is None:
                continue
            chosen[scope.name] = target
        base = state.setdefault(scope.name, {})
        for path in files:
            rel = path.relative_to(scope.live).as_posix()
            if path.name in JUNK_NAMES or JUNK_DIRS.intersection(rel.split("/")):
                continue
            tracked = rel in scope.sources()
            dest_layer = scope.layer_of(rel) if tracked and not layer else chosen[scope.name]
            dst = scope.root / dest_layer / rel
            if tracked and INTERACTIVE and not questionary.confirm(
                    f"  Already tracked ({dest_layer}): {rel} — overwrite the repo copy?",
                    default=False).ask():
                continue
            data = _read(path, sudo=scope.sudo) or b""
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.is_symlink():
                dst.unlink()
            if path.is_symlink():
                os.symlink(os.readlink(path), dst)
            else:
                dst.write_bytes(data)
                shutil.copymode(path, dst)
            base[rel] = _blob_hash(data)
            added.append(dst)
            console.print(f"  [green]✓[/green]  {scope.display(rel)}  [dim]→ {dest_layer}[/dim]")
        scope.refresh()
    _save_state(state)
    if added:
        rels = " ".join(str(p.relative_to(DOTFILES_DIR)) for p in added[:3])
        console.print(f"  [dim]Commit:  git add {rels}{' ...' if len(added) > 3 else ''} && git commit[/dim]")

def cmd_move(args: list[str]) -> None:
    """`move <path> <layer>` — git-mv tracked files between layers (promote/demote)."""
    if len(args) != 2:
        console.print("[red]Usage:[/red] dot move <path> <layer>   "
                      f"[dim](layers here: {', '.join(home_scope().layers)})[/dim]")
        sys.exit(1)
    path_str, layer = args
    loc = _locate(path_str)
    if not loc:
        console.print(f"[red]Not under $HOME{' or /etc' if IS_LINUX else ''}:[/red] {path_str}")
        sys.exit(1)
    scope, rel = loc
    if layer not in scope.layers:
        console.print(f"[red]Layer '{layer}' doesn't apply on this machine.[/red] "
                      f"Available: {', '.join(scope.layers)}")
        sys.exit(1)
    moves = [(r, scope.layer_of(r)) for r in scope.tracked()
             if r == rel or r.startswith(rel.rstrip("/") + "/")]
    if not moves:
        console.print(f"[red]Nothing tracked at[/red] {scope.display(rel)}")
        sys.exit(1)
    for r, cur in moves:
        if cur == layer:
            continue
        src, dst = scope.root / cur / r, scope.root / layer / r
        dst.parent.mkdir(parents=True, exist_ok=True)
        if subprocess.run(["git", "mv", str(src), str(dst)], cwd=DOTFILES_DIR,
                          capture_output=True).returncode != 0:
            shutil.move(src, dst)
        console.print(f"  [green]✓[/green]  {scope.display(r)}  [dim]{cur} → {layer}[/dim]")
    scope.refresh()

# ── modes ─────────────────────────────────────────────────────────────────────
def _step(title: str, desc: str = "") -> None:
    console.print(f"\n[bold]▸ {title}[/bold]  [dim]{desc}[/dim]")

def mode_sync() -> None:
    update_repo()
    do_sync("both")

def mode_apply() -> None:
    do_sync("apply")

def mode_save() -> None:
    do_sync("save")

def mode_install() -> None:
    mgr = {"macos": "brew", "arch": "yay"}.get(OS, "unknown")
    _step("Packages", f"missing ones, via {mgr}")
    install_packages()
    _step("Dotfiles", "repo → this machine")
    do_sync("apply")
    _step("Shell tooling", "tmux tpm · fish plugins")
    setup_shell_tooling()
    console.print("\n[green]✓[/green]  machine set up")

def mode_review() -> None:
    """See every diff in one scroll, then pick which files to move."""
    items = collect()
    movable = [(s, e) for s, e in items if e.kind in ("new", "repo", "local")]
    if not movable and not any(e.kind == "conflict" for _, e in items):
        console.print("  [green]✓[/green]  in sync")
        return
    if not INTERACTIVE:
        console.print("[red]review needs a terminal[/red] — use `dot diff` / `dot sync`")
        sys.exit(1)
    with console.pager(styles=True):
        for s, e in items:
            if e.kind in ("same", "blocked"):
                continue
            console.print(f"\n{KIND_LABEL[e.kind][0]} [bold]{s.display(e.rel)}[/bold]  "
                          f"[dim]{KIND_LABEL[e.kind][1]} · {escape('[' + e.layer + ']')}[/dim]")
            if e.live is None:
                console.print(f"  [dim]new file — {_diff_stat(e)}[/dim]")
            else:
                show_diff(s, e)
    chosen: dict[str, set[str]] = {}
    if movable:
        arrow = {"new": "+", "repo": "↓", "local": "↑"}
        picked = questionary.checkbox(
            "Move which files?  (space toggles · enter confirms)",
            choices=[questionary.Choice(
                title=[("", f"{arrow[e.kind]} {s.display(e.rel)}"),
                       ("fg:ansibrightblack", f"   {_diff_stat(e)}")],
                value=(s.name, e.rel), checked=True) for s, e in movable],
            qmark="").ask()
        if picked is None:
            raise KeyboardInterrupt
        for name, rel in picked:
            chosen.setdefault(name, set()).add(rel)
    do_sync("both", chosen)

def mode_profile() -> None:
    cmd_profile([])

MODES: dict[str, Callable[[], None]] = {
    "sync": mode_sync, "apply": mode_apply, "save": mode_save, "install": mode_install,
    "review": mode_review, "profile": mode_profile,
}
ALIASES = {"copy": "apply", "pull": "save", "ui": ""}

def menu() -> None:
    """Plain `dot`: the dashboard, then a short menu that matches what it shows."""
    items = collect()
    dashboard(items)
    n_in = sum(1 for _, e in items if e.kind in ("new", "repo"))
    n_out = sum(1 for _, e in items if e.kind == "local")
    n_bad = sum(1 for _, e in items if e.kind == "conflict")
    parts = [f"{verb} {n}" for verb, n in (("apply", n_in), ("save", n_out), ("resolve", n_bad)) if n]
    choices = [_choice("Sync", ("pull, then " + " · ".join(parts)) if parts
                       else "pull the repo — nothing to move", "sync")]
    if parts:
        choices.append(_choice("Review", "see the diffs, choose which files move", "review"))
    choices += [_choice("Set up this machine", "packages · dotfiles · shell tooling", "install"),
                _choice("Trust level", f"now: {PROFILE_NAME}", "profile"),
                _choice("Quit", "", "quit")]
    choice = questionary.select("", choices=choices, qmark="", pointer="›", instruction=" ").ask()
    if choice in (None, "quit"):
        return
    console.print()
    MODES[choice]()

# ── entry point ───────────────────────────────────────────────────────────────
def main() -> None:
    global VERBOSE
    args = [a for a in sys.argv[1:] if a not in ("-v", "--verbose")]
    VERBOSE = len(args) != len(sys.argv) - 1
    cmd = ALIASES.get(args[0].lstrip("-"), args[0].lstrip("-")) if args else None

    if cmd == "profile":
        cmd_profile(args[1:])
        return

    if PROFILE_NAME is None:
        if not INTERACTIVE:
            console.print("[red]No trust profile chosen for this machine.[/red] "
                          f"Run `dot profile <{'|'.join(PROFILES)}>` first.")
            sys.exit(1)
        choose_profile()
        console.print()

    if cmd == "add":
        rest, layer = args[1:], None
        if "--to" in rest:
            i = rest.index("--to")
            layer = rest[i + 1] if i + 1 < len(rest) else None
            rest = rest[:i] + rest[i + 2:]
        if not rest:
            console.print("[red]Usage:[/red] dot add [--to LAYER] <path...>")
            sys.exit(1)
        cmd_add(rest, layer)
    elif cmd == "move":
        cmd_move(args[1:])
    elif cmd == "diff":
        cmd_diff(args[1:])
    elif cmd == "status":
        cmd_status("--all" in args)
    elif cmd in MODES:
        console.print(f"[bold cyan]dot[/bold cyan]  [dim]{OS} · {PROFILE_NAME}[/dim]\n")
        MODES[cmd]()
    elif cmd:
        console.print(f"[red]Unknown command:[/red] {args[0]}\n"
                      f"  Valid: {' | '.join(['status', 'diff', *MODES, 'add', 'move'])}")
        sys.exit(1)
    elif not INTERACTIVE:
        console.print("[red]No command given and stdin isn't a terminal.[/red] "
                      f"Valid: {' | '.join(['status', 'diff', *MODES])}")
        sys.exit(1)
    else:
        menu()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.print("\n[yellow]Cancelled.[/yellow]")
        sys.exit(130)
