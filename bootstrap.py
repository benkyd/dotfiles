#!/usr/bin/env python3
"""
bootstrap.py — Dotfiles manager for Ben's machines.

OVERVIEW
--------
This script is the single entry point for setting up and maintaining any of
Ben's machines (macOS or Arch Linux). It handles three concerns:

  1. Packages   — installing formulae/casks (brew) or AUR packages (yay)
  2. Tooling    — shell plugins, tmux plugins, etc. declared in setup.toml
  3. Dotfiles   — rsyncing the overlay directory (home/<user>/) into $HOME,
                  and optionally /etc on Linux

DESIGN DECISIONS
----------------
- OS is the only variation axis. All Macs are identical; all Arch machines
  are identical. There are no per-hostname overrides.
- The repo's overlay directory IS the manifest. Any file placed under
  home/<user>/ will be synced to $HOME. Use `add` to track new files.
- Backups are always taken before overwriting ($HOME/dotfiles.bak/).
- When syncing, files that are NEWER at the destination (system) than in the
  repo are flagged for per-file review rather than silently overwritten.
  This protects edits made on a work machine that haven't been pulled yet.
- setup.toml holds declarative tooling config (fish/tmux plugins).
  Packages stay in packages/*.txt so they're easy to grep and diff.

USAGE
-----
  python3 bootstrap.py                 → interactive TUI
  python3 bootstrap.py install         → full setup (non-interactive)
  python3 bootstrap.py copy            → sync dotfiles only
  python3 bootstrap.py pull            → save local edits back to repo
  python3 bootstrap.py status          → check drift, no changes made
  python3 bootstrap.py add <path>      → start tracking a new file

STRUCTURE
---------
  packages/brew.txt        formulae for all Macs
  packages/brew-casks.txt  cask apps for all Macs
  packages/arch.txt        packages for all Arch machines
  setup.toml               fish/tmux plugin declarations
  home/<user>/             dotfile overlay (mirrors $HOME structure)
  etc/                     optional /etc overlay (applied with sudo)
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
        # PEP 668 (Arch, Ubuntu 23+) marks the system Python as externally
        # managed, requiring --break-system-packages for user-level installs
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

from dataclasses import dataclass
from typing import Callable
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text
import questionary

console = Console()

# ── paths ─────────────────────────────────────────────────────────────────────
DOTFILES_DIR = Path(__file__).parent.resolve()
BACKUP_DIR   = Path.home() / "dotfiles.bak"   # originals go here before overwrite
USERNAME     = os.environ.get("USER", os.environ.get("LOGNAME", "benk"))

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

# ── OS-specific path exclusions ───────────────────────────────────────────────
# Some paths in the overlay only make sense on a specific OS.
# These are excluded from syncing when we're on a different OS.
#
# Format: { "owner_os": ["path/to/exclude/"] }
#
# Current rules:
#   macOS only  → Library/               (iTerm2 prefs, macOS app support)
#   Linux only  → .config/wezterm/       (WezTerm is the Linux terminal;
#                                          iTerm2 is used on macOS instead)

OS_ONLY: dict[str, list[str]] = {
    "macos": ["Library/"],
    "linux": [".config/wezterm/"],
    "arch":  [".config/wezterm/"],
}

def _load_dotignore() -> list[str]:
    """
    Read ~/.dotignore and return patterns to exclude from syncing.
    Each non-blank, non-comment line becomes an rsync --exclude pattern.
    """
    p = Path.home() / ".dotignore"
    if not p.exists():
        return []
    return [
        ln.strip() for ln in p.read_text().splitlines()
        if ln.strip() and not ln.startswith("#")
    ]

def home_excludes() -> list[str]:
    """
    Build rsync --exclude flags for paths that don't belong on this OS
    and paths listed in ~/.dotignore on this machine.
    """
    flags: list[str] = []
    for owner_os, paths in OS_ONLY.items():
        if OS != owner_os:
            for p in paths:
                flags += ["--exclude", p]
    for p in _load_dotignore():
        flags += ["--exclude", p]
    return flags

# ── rsync helpers ─────────────────────────────────────────────────────────────
# We use rsync for all file syncing because it handles:
#   - incremental transfers (only changed files)
#   - directory trees
#   - backups (--backup --backup-dir)
#   - dry-run previews (--dry-run --itemize-changes)
#
# The --itemize-changes format is: YXcstpogba path
#   Y = update type: > (transfer to dst), < (transfer from dst)
#   X = file type:   f (file), d (dir), L (symlink), ...
#   flags = 9 chars; all '+' means new file; any other char means attribute changed
#
# We parse this output to distinguish new files from overwrites,
# and to decide which overwrites need per-file confirmation.

def _parse_changes(rsync_output: str) -> list[tuple[str, str]]:
    """
    Parse rsync --itemize-changes output into (kind, path) tuples.
    Only regular files transferred TO the destination ('>f') are included.

    kind values:
      'new'     — file doesn't exist at dst yet (flags are all '+')
      'changed' — file exists at dst and will be overwritten
    """
    results = []
    for line in rsync_output.splitlines():
        # Only care about files being sent to the destination ('>f...')
        if not line.startswith(">f"):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        flag, path = parts
        # All-'+' flags = brand new file; any variation = existing file updated
        kind = "new" if "+++++++++" in flag else "changed"
        results.append((kind, path))
    return results

def confirm_rsync(src: str, dst: str, flags: list[str], *, sudo: bool = False, label: str = "") -> bool:
    """
    Smart rsync wrapper that protects against accidentally overwriting newer work.

    Flow:
      1. Dry-run rsync to find what would change
      2. For files that already exist at dst:
           - If dst is NEWER than src → add to per-file confirmation list
             (unchecked by default, so the user must actively choose to overwrite)
           - If dst is OLDER than src → overwrite silently (repo wins)
      3. Run the real rsync, excluding any files the user declined to overwrite

    Returns True if the sync ran, False if the user cancelled.
    """
    all_args = flags + [src, dst]

    # Dry run first — no files are touched
    dry = subprocess.run(
        ["rsync", "--dry-run", "--itemize-changes"] + all_args,
        capture_output=True, text=True,
    )
    changes    = _parse_changes(dry.stdout)
    overwrites = [p for kind, p in changes if kind == "changed"]

    extra_excludes: list[str] = []

    if overwrites:
        src_p = Path(src.rstrip("/"))
        dst_p = Path(dst.rstrip("/"))

        newer_at_dst: list[str] = []   # dst is newer → needs review
        auto_count = 0                 # dst is older → safe to overwrite

        for rel in overwrites:
            src_f, dst_f = src_p / rel, dst_p / rel
            if (dst_f.exists() and src_f.exists()
                    and dst_f.stat().st_mtime > src_f.stat().st_mtime):
                newer_at_dst.append(rel)
            else:
                auto_count += 1

        if newer_at_dst:
            # Inform the user about silent overwrites before showing the checkbox
            if auto_count:
                console.print(
                    f"  [dim]Auto-overwriting {auto_count} older file(s) — "
                    f"repo is newer, no action needed[/dim]"
                )
            console.print()
            # Show a checkbox for files where the system has newer edits.
            # All unchecked by default — the user must opt IN to overwrite.
            prefix = f"[{label}] " if label else ""
            selected = questionary.checkbox(
                f"{prefix}These files are newer on this machine than in the repo.\n"
                f"  Check any you want to overwrite with the repo version:",
                choices=[
                    questionary.Choice(
                        title=f"{r}  [dim](system is newer)[/dim]",
                        value=r,
                        checked=False,   # opt-in, not opt-out
                    )
                    for r in newer_at_dst
                ],
            ).ask()
            if selected is None:
                console.print("[yellow]  Cancelled.[/yellow]")
                return False
            # Exclude files the user chose NOT to overwrite
            for rel in newer_at_dst:
                if rel not in selected:
                    extra_excludes += ["--exclude", rel]

    cmd = (["sudo"] if sudo else []) + ["rsync"] + extra_excludes + all_args
    subprocess.run(cmd, check=True)
    return True

# ── directory bootstrap ───────────────────────────────────────────────────────

def create_home_dirs() -> None:
    """
    Ensure standard XDG and home directories exist before syncing.
    rsync will fail if a parent directory doesn't exist.
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
        if not questionary.confirm("  Continue anyway?", default=False).ask():
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
    Install Homebrew if not present, then install all formulae from brew.txt
    and all casks from brew-casks.txt.

    brew.txt  → `brew install <pkg>`          (CLI tools, libraries)
    brew-casks.txt → `brew install --cask <app>`  (GUI apps, fonts)
    """
    if not shutil.which("brew"):
        console.print("  [bold]Homebrew not found — installing...[/bold]")
        subprocess.run(
            ["/bin/bash", "-c",
             "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"],
            check=True,
        )
    pkgs = _read_packages(DOTFILES_DIR / "packages" / "brew.txt")
    console.print(f"  Installing [bold]{len(pkgs)}[/bold] formulae...")
    for pkg in pkgs:
        _install_one(["brew", "install"], pkg)
    casks = _read_packages(DOTFILES_DIR / "packages" / "brew-casks.txt")
    if casks:
        console.print(f"  Installing [bold]{len(casks)}[/bold] casks...")
        for cask in casks:
            _install_one(["brew", "install", "--cask"], cask)

def _install_arch() -> None:
    """
    Bootstrap yay (AUR helper) if not present, then install all packages
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
    pkgs = _read_packages(DOTFILES_DIR / "packages" / "arch.txt")
    console.print(f"  Installing [bold]{len(pkgs)}[/bold] packages...")
    for pkg in pkgs:
        _install_one(["yay", "-S", "--needed", "--noconfirm"], pkg)

# ── shell tooling ─────────────────────────────────────────────────────────────
# "Tooling" means things that aren't packages but need to be set up once:
# tmux plugin manager, oh-my-fish, fisher, and the plugins declared in setup.toml.

def setup_shell_tooling() -> None:
    """Set up tmux and fish tooling in sequence."""
    _setup_tmux()
    _setup_fish()

def _setup_tmux() -> None:
    """
    Clone tpm (Tmux Plugin Manager) if not present, then install any tmux
    plugins listed in setup.toml [tmux] plugins via tpm's headless install script.

    tpm lives at ~/.tmux/plugins/tpm.
    Plugins are installed to ~/.tmux/plugins/<plugin-name>.
    The headless install script is at ~/.tmux/plugins/tpm/bin/install_plugins.
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

    plugins = SETUP.get("tmux", {}).get("plugins", [])
    if plugins:
        install_script = tpm / "bin" / "install_plugins"
        if install_script.exists():
            console.print(f"  Installing {len(plugins)} tmux plugin(s) headlessly...")
            subprocess.run([str(install_script)], capture_output=True)
            console.print("  [green]✓[/green]  tmux plugins")
        else:
            # Fallback: manual instruction if the script isn't present
            console.print("  [yellow]![/yellow]  Run [dim]<C-b>I[/dim] inside tmux to install plugins")

def _setup_fish() -> None:
    """
    Set up the fish shell plugin ecosystem:
      1. oh-my-fish (OMF) — theming and utility functions
      2. fisher — fish plugin manager (manages plugins declared in setup.toml)
      3. fish plugins from setup.toml [fish] plugins

    Skipped entirely if fish is not installed on this machine.
    Fisher install is idempotent — it only installs plugins not already present.
    """
    if not shutil.which("fish"):
        console.print("  [dim]fish not installed — skipping fish setup[/dim]")
        return

    omf = Path.home() / ".local" / "share" / "omf"
    if not omf.exists():
        console.print("  Installing oh-my-fish...")
        subprocess.run(["fish", "-c", "curl -L https://get.oh-my.fish | fish"], check=True)
    else:
        console.print("  [green]✓[/green]  oh-my-fish")

    # Check if fisher is available as a fish function
    result = subprocess.run(["fish", "-c", "type -q fisher"], capture_output=True)
    if result.returncode != 0:
        console.print("  Installing fisher...")
        subprocess.run(
            ["fish", "-c",
             "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/"
             "functions/fisher.fish | source && fisher install jorgebucaran/fisher"],
            check=True,
        )
    else:
        console.print("  [green]✓[/green]  fisher")

    # Install any fish plugins declared in setup.toml that aren't already installed
    plugins = SETUP.get("fish", {}).get("plugins", [])
    if plugins:
        installed_r = subprocess.run(
            ["fish", "-c", "fisher list"], capture_output=True, text=True
        )
        installed  = set(installed_r.stdout.strip().splitlines())
        to_install = [p for p in plugins if p not in installed]
        if to_install:
            console.print(f"  Installing {len(to_install)} fish plugin(s)...")
            subprocess.run(
                ["fish", "-c", f"fisher install {' '.join(to_install)}"],
                check=True,
            )
        console.print("  [green]✓[/green]  fish plugins")

# ── sync: repo → home (copy / install) ───────────────────────────────────────

def sync_to_home() -> None:
    """
    Sync the overlay directory (home/<user>/) into $HOME.
    Original files are backed up to ~/dotfiles.bak/home/ before overwriting.
    OS-specific paths are excluded via home_excludes().
    """
    src = overlay_home()
    dst = Path.home()
    (BACKUP_DIR / "home").mkdir(parents=True, exist_ok=True)
    flags = [
        "-av", "--itemize-changes",
        "--backup", f"--backup-dir={BACKUP_DIR / 'home'}",
        *home_excludes(),
    ]
    console.print(
        f"  [bold]Syncing[/bold] [cyan]{src.relative_to(DOTFILES_DIR)}[/cyan]"
        f" → [cyan]~[/cyan]"
    )
    confirm_rsync(f"{src}/", f"{dst}/", flags, label="repo → home")

# ── sync: home → repo (pull) ─────────────────────────────────────────────────

def sync_to_repo() -> None:
    """
    Pull live config from $HOME back into the overlay (home/<user>/).
    Only files that already exist in the overlay are candidates — we build
    an explicit file list from the overlay and pass it via --files-from.

    Why --files-from instead of --existing:
      --existing tells rsync "only update files at dst that exist there", but
      rsync still traverses the ENTIRE source tree to find candidates. On a
      large home directory this is slow, verbose, and can create ghost
      directories in the overlay that become "tracked" on the next run.
      --files-from is an explicit manifest: rsync only touches those paths.

    Also pulls /etc if an etc/ overlay directory exists in the repo.
    """
    import tempfile

    src, dst = Path.home(), overlay_home()

    # Build explicit file list from the overlay (relative to overlay root)
    tracked = [
        str(f.relative_to(dst))
        for f in dst.rglob("*")
        if f.is_file() and not any(
            str(f.relative_to(dst)).startswith(excl.lstrip("/"))
            for excl in home_excludes()[1::2]   # every other element is the path
        )
    ]

    if not tracked:
        console.print("  [dim]No files tracked in overlay — nothing to pull.[/dim]")
        return

    console.print(
        f"  [bold]Pulling[/bold] [cyan]~[/cyan]"
        f" → [cyan]{dst.relative_to(DOTFILES_DIR)}[/cyan]"
        f"  [dim]({len(tracked)} tracked files)[/dim]"
    )

    # Write the manifest to a temp file and pass it to rsync
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as fh:
        fh.write("\n".join(tracked))
        manifest = fh.name

    try:
        flags = [
            "-av", "--itemize-changes",
            f"--files-from={manifest}",   # only sync these exact paths
            "--update",   # skip files where dst (overlay) is newer than src (home)
        ]
        confirm_rsync(f"{src}/", f"{dst}/", flags, label="home → repo")
    finally:
        Path(manifest).unlink(missing_ok=True)

    etc_dir = DOTFILES_DIR / "etc"
    if etc_dir.is_dir():
        etc_tracked = [
            str(f.relative_to(etc_dir))
            for f in etc_dir.rglob("*") if f.is_file()
        ]
        console.print(f"  [bold]Pulling[/bold] [cyan]/etc[/cyan] → [cyan]etc/[/cyan]")
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as fh:
            fh.write("\n".join(etc_tracked))
            etc_manifest = fh.name
        try:
            confirm_rsync(
                "/etc/", f"{etc_dir}/",
                ["-av", "--itemize-changes", f"--files-from={etc_manifest}", "--update"],
                sudo=True, label="/etc → repo",
            )
        finally:
            Path(etc_manifest).unlink(missing_ok=True)

# ── sync: etc/ → /etc ─────────────────────────────────────────────────────────

def sync_etc() -> None:
    """
    Apply the etc/ overlay to /etc on the system (requires sudo).
    Original /etc files are backed up to ~/dotfiles.bak/etc/ before overwriting.
    This is exposed as an optional stage in mode_install; it's excluded from
    mode_copy because /etc changes are usually intentional and should be reviewed.
    """
    etc_dir = DOTFILES_DIR / "etc"
    files   = [f for f in etc_dir.rglob("*") if f.is_file()]
    console.print("  [bold]System config files to apply:[/bold]")
    for f in files:
        console.print(f"    [dim]/{f.relative_to(DOTFILES_DIR)}[/dim]")
    console.print()
    (BACKUP_DIR / "etc").mkdir(parents=True, exist_ok=True)
    confirm_rsync(
        f"{etc_dir}/", "/etc/",
        ["-av", "--itemize-changes", "--backup", f"--backup-dir={BACKUP_DIR / 'etc'}"],
        sudo=True, label="etc → /etc",
    )

def _has_etc() -> bool:
    """Return True if the repo has an etc/ overlay with at least one file."""
    etc_dir = DOTFILES_DIR / "etc"
    return etc_dir.is_dir() and any(f for f in etc_dir.rglob("*") if f.is_file())

# ── status command ────────────────────────────────────────────────────────────
# Status is read-only — it never modifies any files.
# It answers the question: "how does this machine differ from the repo?"

def cmd_status() -> None:
    """
    Show a full drift report: packages, dotfiles, and tooling.
    No files are written or modified.
    """
    console.print(Panel(
        "[bold]Status[/bold]  [dim]comparing this machine against the repo — "
        "no changes will be made[/dim]",
        border_style="bright_blue", padding=(0, 1),
    ))

    console.rule("[bold]Packages[/bold]", style="bright_blue")
    _status_packages()

    console.rule("[bold]Dotfiles[/bold]", style="bright_blue")
    _status_dotfiles()

    console.rule("[bold]Tooling[/bold]", style="bright_blue")
    _status_tooling()

    console.rule(style="bright_blue")

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
        installed_formulae = set(
            subprocess.check_output(["brew", "list", "--formula"], text=True).splitlines()
        )
        installed_casks = set(
            subprocess.check_output(["brew", "list", "--cask"], text=True).splitlines()
        )
        _status_pkg_list(
            "formulae",
            _read_packages(DOTFILES_DIR / "packages" / "brew.txt"),
            installed_formulae,
        )
        _status_pkg_list(
            "casks",
            _read_packages(DOTFILES_DIR / "packages" / "brew-casks.txt"),
            installed_casks,
        )
    elif OS in ("arch", "linux"):
        installed = set(subprocess.check_output(["pacman", "-Qq"], text=True).splitlines())
        _status_pkg_list(
            "packages",
            _read_packages(DOTFILES_DIR / "packages" / "arch.txt"),
            installed,
        )
    else:
        console.print("  [dim]Package status not supported on this OS[/dim]")
    console.print()

def _status_pkg_list(label: str, wanted: list[str], installed: set[str]) -> None:
    """Print missing packages individually and summarise installed ones as a count."""
    missing  = [p for p in wanted if p not in installed]
    ok_count = sum(1 for p in wanted if p in installed)
    for p in missing:
        console.print(f"  [red]✗[/red]  {p}  [dim]({label} — not installed)[/dim]")
    console.print(f"  [green]✓[/green]  {ok_count}/{len(wanted)} {label} installed")

def _status_dotfiles() -> None:
    """
    Dry-run rsync repo→home and classify each changed file as:
      new          — in repo, not yet on this machine (copy will add it)
      repo ahead   — repo is newer (copy will update it)
      system ahead — system is newer (pull to capture, or leave it)

    Shows up to 5 examples per category with a count for the rest.
    """
    console.print()
    src = overlay_home()
    dst = Path.home()

    result = subprocess.run(
        ["rsync", "--dry-run", "--itemize-changes", "-av",
         *home_excludes(), f"{src}/", f"{dst}/"],
        capture_output=True, text=True,
    )
    changes = _parse_changes(result.stdout)

    if not changes:
        console.print("  [green]✓[/green]  All dotfiles are up to date")
        console.print()
        return

    new_files     = [p for kind, p in changes if kind == "new"]
    changed_files = [p for kind, p in changes if kind == "changed"]

    # For each changed file, decide which side is "ahead" by mtime
    repo_ahead   = []
    system_ahead = []
    for rel in changed_files:
        dst_f = dst / rel
        src_f = src / rel
        if dst_f.exists() and src_f.exists() and dst_f.stat().st_mtime > src_f.stat().st_mtime:
            system_ahead.append(rel)
        else:
            repo_ahead.append(rel)

    def _show_files(files: list[str], limit: int = 5) -> None:
        for p in files[:limit]:
            console.print(f"       [dim]{p}[/dim]")
        if len(files) > limit:
            console.print(f"       [dim]... and {len(files) - limit} more[/dim]")

    if new_files:
        console.print(
            f"  [blue]+[/blue]   {len(new_files)} file(s) in repo, "
            f"not yet on this machine  [dim](run Copy to apply)[/dim]"
        )
        _show_files(new_files)

    if repo_ahead:
        console.print(
            f"  [cyan]↓[/cyan]   {len(repo_ahead)} file(s) where repo is newer  "
            f"[dim](run Copy to apply)[/dim]"
        )
        _show_files(repo_ahead)

    if system_ahead:
        console.print(
            f"  [yellow]↑[/yellow]   {len(system_ahead)} file(s) where this machine is newer  "
            f"[dim](run Pull to save, or leave as-is)[/dim]"
        )
        _show_files(system_ahead)

    console.print()

def _status_tooling() -> None:
    """
    Check whether tmux tpm, oh-my-fish, fisher, and declared plugins are installed.
    Cross-references setup.toml for expected plugin lists.
    """
    console.print()

    # tmux
    tpm = Path.home() / ".tmux" / "plugins" / "tpm"
    _status_line("tmux plugin manager (tpm)", tpm.exists())
    for plugin in SETUP.get("tmux", {}).get("plugins", []):
        plugin_dir = Path.home() / ".tmux" / "plugins" / plugin.split("/")[-1]
        _status_line(f"  tmux: {plugin}", plugin_dir.exists())

    # fish
    if shutil.which("fish"):
        omf = Path.home() / ".local" / "share" / "omf"
        _status_line("oh-my-fish", omf.exists())
        fisher_ok = subprocess.run(["fish", "-c", "type -q fisher"], capture_output=True)
        _status_line("fisher", fisher_ok.returncode == 0)
        if fisher_ok.returncode == 0:
            installed_r = subprocess.run(
                ["fish", "-c", "fisher list"], capture_output=True, text=True
            )
            installed = set(installed_r.stdout.strip().splitlines())
            for plugin in SETUP.get("fish", {}).get("plugins", []):
                _status_line(f"  fish: {plugin}", plugin in installed)
    else:
        console.print("  [dim]fish not installed — skipping fish tooling check[/dim]")

    console.print()

def _status_line(label: str, ok: bool) -> None:
    """Print a single ✓ / ✗ status line."""
    icon = "[green]✓[/green]" if ok else "[red]✗[/red]"
    console.print(f"  {icon}  {label}")

# ── add command ───────────────────────────────────────────────────────────────

def cmd_add(path_str: str) -> None:
    """
    Start tracking a new file by copying it into the dotfile overlay.

    The file must be under $HOME. Its path relative to $HOME is preserved
    in the overlay, so the sync will deploy it back to the same location.

    Example:
        python3 bootstrap.py add ~/.config/starship.toml
        → copies to home/benk/.config/starship.toml
        → `git add` and commit to make it permanent
    """
    path = Path(path_str).expanduser().resolve()
    if not path.exists():
        console.print(f"[red]File not found:[/red] {path}")
        sys.exit(1)

    try:
        rel = path.relative_to(Path.home())
    except ValueError:
        console.print(
            f"[red]Error:[/red] path must be under $HOME\n"
            f"  Got: {path}\n"
            f"  $HOME: {Path.home()}"
        )
        sys.exit(1)

    dst = overlay_home() / rel
    if dst.exists():
        console.print(f"[yellow]Already tracked:[/yellow] {rel}")
        console.print(f"  [dim]Currently at: {dst}[/dim]")
        if not questionary.confirm("  Overwrite the repo copy?", default=False).ask():
            sys.exit(0)

    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dst)
    console.print(f"  [green]✓[/green]  Tracked: [cyan]~/{rel}[/cyan]")
    console.print(
        f"  [dim]Repo path: {dst.relative_to(DOTFILES_DIR)}[/dim]\n"
        f"  [dim]Commit:    git add {dst.relative_to(DOTFILES_DIR)} && git commit[/dim]"
    )

# ── stage runner ──────────────────────────────────────────────────────────────
# A Stage is a named, describable unit of work within a mode.
# run_stages() shows a checkbox so the user can skip stages they don't need,
# then runs each selected stage with a clear progress header.

@dataclass
class Stage:
    """A discrete unit of work within a mode (e.g. 'Install packages')."""
    key:   str               # unique identifier used for checkbox selection
    title: str               # short display name shown in the checkbox and header
    desc:  str               # one-line description shown alongside the title
    fn:    Callable[[], None]  # the function to call when this stage runs

# Set once at import time: True if a CLI argument was passed (non-interactive mode).
# run_stages() skips the checkbox and runs all stages when this is True.
NON_INTERACTIVE = len(sys.argv) > 1

def run_stages(mode_title: str, mode_desc: str, stages: list[Stage]) -> None:
    """
    Display a mode panel, let the user select which stages to run via checkbox,
    then execute each selected stage with a numbered progress header.

    In non-interactive mode (CLI argument provided) all stages run without prompting.

    The stage rule format is:  Stage N/M  Title  description
    This makes it easy to see at a glance where you are in a multi-stage run.
    """
    console.print(Panel(
        f"[bold]{mode_title}[/bold]\n[dim]{mode_desc}[/dim]",
        border_style="bright_blue", padding=(0, 1),
    ))
    console.print()

    if NON_INTERACTIVE:
        # Skip the checkbox when called from the command line (scripted / CI use)
        to_run = stages
    else:
        selected_keys = questionary.checkbox(
            "Select which stages to run  "
            "[dim](space to toggle, enter to confirm, ctrl-c to cancel)[/dim]",
            choices=[
                questionary.Choice(
                    title=f"{s.title}  [dim]— {s.desc}[/dim]",
                    value=s.key,
                    checked=True,   # all stages selected by default
                )
                for s in stages
            ],
        ).ask()

        if selected_keys is None:
            # questionary returns None on Ctrl-C
            console.print("\n[yellow]Cancelled.[/yellow]")
            sys.exit(0)
        if not selected_keys:
            console.print("[yellow]No stages selected — nothing to do.[/yellow]")
            return

        to_run = [s for s in stages if s.key in selected_keys]

    total = len(to_run)
    for i, stage in enumerate(to_run, 1):
        console.print()
        console.rule(
            f"[bold bright_blue]Stage {i} of {total}[/bold bright_blue]"
            f"  [bold]{stage.title}[/bold]  [dim]{stage.desc}[/dim]",
            style="bright_blue",
        )
        console.print()
        stage.fn()

    console.print()
    console.rule("[bold green]All done[/bold green]", style="green")
    console.print()

# ── modes ─────────────────────────────────────────────────────────────────────
# Each mode is a curated list of stages suited to a particular intent.
# Modes are presented in the TUI select and can also be called from the CLI.

def _stage_sync_dotfiles() -> None:
    """Ensure home dirs exist then sync dotfiles. Used in both install and copy."""
    create_home_dirs()
    sync_to_home()

def mode_install() -> None:
    """
    Full machine setup: packages → tooling → dotfiles → /etc (if present).
    Intended for bootstrapping a new machine from scratch.
    All stages are shown in the checkbox; deselect any you want to skip.
    """
    pkg_mgr = {"macos": "brew", "arch": "yay"}.get(OS, "unknown")
    stages = [
        Stage("packages", "Install packages", f"via {pkg_mgr}",           install_packages),
        Stage("tooling",  "Shell tooling",    "tmux tpm · fish plugins",  setup_shell_tooling),
        Stage("dotfiles", "Sync dotfiles",    "repo → home",              _stage_sync_dotfiles),
    ]
    if _has_etc():
        stages.append(Stage("etc", "Sync /etc", "requires sudo", sync_etc))
    run_stages(
        "Set up this machine",
        "Install packages, shell tooling, and sync dotfiles from the repo",
        stages,
    )

def mode_copy() -> None:
    """
    Apply dotfiles from the repo to this machine.
    Skips packages and shell tooling — use this on a machine that's already set up
    when you just want to push a config change out.
    """
    run_stages(
        "Apply dotfiles",
        "Sync repo → home (skip packages and shell tooling)",
        [Stage("dotfiles", "Sync dotfiles", "repo → home", _stage_sync_dotfiles)],
    )

def mode_pull() -> None:
    """
    Pull edits made on this machine back into the repo.
    Only files already tracked in the overlay are updated (no new files are added).
    Use `add` to start tracking a new file.
    Files newer on this machine will be shown for per-file confirmation.
    """
    run_stages(
        "Save changes",
        "Pull edits from this machine back into the repo",
        [Stage("pull", "Pull config", "home + /etc → repo", sync_to_repo)],
    )

# ── mode registry ─────────────────────────────────────────────────────────────
# Modes are keyed by their CLI name. Each entry is (display_title, description, fn).
# The TUI select and the CLI dispatcher both read from this dict,
# so adding a new mode here is the only change needed.

MODES: dict[str, tuple[str, str, Callable[[], None]]] = {
    "install": (
        "Set up this machine",
        "install packages, shell tooling, and sync dotfiles",
        mode_install,
    ),
    "copy": (
        "Apply dotfiles",
        "push repo changes to this machine (skip packages)",
        mode_copy,
    ),
    "pull": (
        "Save changes",
        "pull edits made on this machine back into the repo",
        mode_pull,
    ),
    "status": (
        "Check status",
        "see what's different between this machine and the repo",
        cmd_status,
    ),
}

# ── entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    """
    Parse CLI arguments or show the interactive TUI.

    CLI usage (non-interactive, skips all checkboxes):
      bootstrap.py install | copy | pull | status
      bootstrap.py add <path>

    Interactive usage (no arguments):
      Shows a mode-select menu, then a stage-select checkbox.
    """
    # ── header ──
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

    # ── CLI: bootstrap.py add <path> ──
    if len(sys.argv) > 1 and sys.argv[1] == "add":
        if len(sys.argv) < 3:
            console.print(
                "[red]Usage:[/red] bootstrap.py add [cyan]<path>[/cyan]\n"
                "  Example: bootstrap.py add ~/.config/starship.toml"
            )
            sys.exit(1)
        cmd_add(sys.argv[2])
        return

    # ── CLI: bootstrap.py <mode> ──
    if len(sys.argv) > 1:
        key = sys.argv[1].lstrip("-")   # accept --install as well as install
        if key in MODES:
            MODES[key][2]()
            return
        console.print(
            f"[red]Unknown command:[/red] {sys.argv[1]}\n"
            f"  Valid commands: add <path> | {' | '.join(MODES)}"
        )
        sys.exit(1)

    # ── TUI: interactive mode select ──
    console.print("[dim]Use arrow keys to navigate, enter to select.[/dim]\n")
    choice = questionary.select(
        "What would you like to do?",
        choices=[
            questionary.Choice(
                title=f"{title}  [dim]— {desc}[/dim]",
                value=key,
            )
            for key, (title, desc, _) in MODES.items()
        ],
    ).ask()

    if choice is None:
        # Ctrl-C
        console.print("\n[yellow]Cancelled.[/yellow]")
        sys.exit(0)

    MODES[choice][2]()

if __name__ == "__main__":
    main()
