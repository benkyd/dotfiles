# dotfiles

Centralized database of how my machines should be set up. All Macs are identical to each other, all Arch machines are identical to each other. OS is the only axis of variation.

```
dotfiles/
  home/benk/            mirrors $HOME — files here get synced to the machine
  etc/                  mirrors /etc — applied with sudo on Linux
  packages/
    brew.txt            Homebrew formulae (all Macs)
    brew-casks.txt      Homebrew casks (all Macs)
    arch.txt            yay packages (all Arch machines)
  themes/
    catppuccin-iterm/   submodule: catppuccin/iterm
  setup.toml            declarative tooling config (fish + tmux plugins)
  bootstrap.py          the manager — run this
```

## setup

```bash
git clone --recurse-submodules git@github.com:benkyd/dotfiles.git ~/dotfiles
cd ~/dotfiles
python3 bootstrap.py
```

Dependencies (`rich`, `questionary`) are auto-installed on first run.

## usage

Running `python3 bootstrap.py` drops you into a TUI. Pick a mode:

- **Sync** — `git pull`, then move every change in whichever direction it needs to go. the everyday option.
- **Check status** — see what's drifted. nothing is changed.
- **Show diffs** — see exactly what differs, file by file.
- **Apply dotfiles** — repo → machine only. local edits are kept.
- **Save changes** — machine → repo only, then offers to commit.
- **Set up this machine** — install missing packages, deploy dotfiles, set up shell tooling. use this on a fresh machine.

Or pass a mode directly to skip the TUI:

```bash
python3 bootstrap.py sync
python3 bootstrap.py status
python3 bootstrap.py diff [path...]
python3 bootstrap.py apply                          # alias: copy
python3 bootstrap.py save                           # alias: pull
python3 bootstrap.py install
python3 bootstrap.py add ~/.config/something.conf   # start tracking files or dirs
```

## how sync decides what's newer

Not by timestamps — git clone/checkout/pull stamp everything with "now". Files are compared by content against the version last synced on this machine (kept in `~/.local/state/dotfiles/state.json`):

- only the repo changed → deployed
- only this machine changed → saved into the repo
- both changed → you choose: view the diff, take either side, or merge in `nvim -d`

On a machine with no sync state yet, a file matching any version in its git history counts as "repo is newer"; anything else asks. Non-interactive runs never guess — they skip and list what needs a decision. Anything overwritten is backed up to `~/dotfiles.bak/<timestamp>/`.

## per-machine exclusions

List paths in `~/.dotignore` to never sync them on that machine (gitignore-style: `dir/`, `/anchored/path`, `*.glob`).

## OS-specific paths

Some paths only make sense on one OS and are excluded automatically:

- `Library/` — macOS only (iTerm2 prefs, etc.)
- `.config/wezterm/` — Linux only (iTerm2 is used on Mac)
- `etc/` — Linux only, applied with sudo (`*.md` files there are notes and aren't deployed)

## themes

Catppuccin Mocha is the colour scheme. The iTerm2 colour preset lives at `themes/catppuccin-iterm/colors/catppuccin-mocha.itermcolors`. Import it via iTerm2 → Profiles → Colors → Color Presets → Import.
