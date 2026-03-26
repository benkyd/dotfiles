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

- **Set up this machine** — install packages, shell tooling, sync dotfiles. use this on a fresh machine.
- **Apply dotfiles** — push repo → `$HOME`. skips packages.
- **Save changes** — pull edits you made on this machine back into the repo.
- **Check status** — see what's drifted. nothing is changed.

Or pass a mode directly to skip the TUI:

```bash
python3 bootstrap.py install
python3 bootstrap.py copy
python3 bootstrap.py pull
python3 bootstrap.py status
python3 bootstrap.py add ~/.config/something.conf   # start tracking a new file
```

## per-file variation

If you've edited something on a work machine and don't want to clobber it or pull it back, the sync steps show a per-file checkbox for any file that's newer on the machine than in the repo. just uncheck what you want to skip.

## OS-specific paths

Some paths only make sense on one OS and are excluded automatically:

- `Library/` — macOS only (iTerm2 prefs, etc.)
- `.config/wezterm/` — Linux only (iTerm2 is used on Mac)

## themes

Catppuccin Mocha is the colour scheme. The iTerm2 colour preset lives at `themes/catppuccin-iterm/colors/catppuccin-mocha.itermcolors`. Import it via iTerm2 → Profiles → Colors → Color Presets → Import.
