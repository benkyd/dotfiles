# Dotfiles

Mirrors `$HOME`. Symlinked via `bootstrap.sh`.

```
git clone git@github.com:benkyd/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

The bootstrap script will:
1. Detect your OS (macOS or Arch Linux)
2. Optionally install packages (Homebrew on macOS, yay on Arch)
3. Install tmux plugin manager and fisher (fish plugin manager)
4. Symlink all dotfiles into `$HOME` (existing files backed up to `~/dotfiles.bak/`)
5. Optionally copy system configs from `etc/` to `/etc/` (with sudo, prompted)

Works on both macOS and Linux — wezterm, tmux, and fish auto-detect the platform.
