# Dotfiles

Filesystem overlay. Structure mirrors actual paths on disk.

```
dotfiles/
  home/benk/          -> symlinked into $HOME
    .config/nvim/
    .config/fish/
    .config/wezterm/
    .tmux.conf
    .vimrc
    ...
  etc/                -> copied into /etc (prompted, needs sudo)
    fstab
    nginx/nginx.conf
  packages/           -> package lists for brew/yay
  bootstrap.sh        -> does everything
```

## Usage

```
git clone git@github.com:benkyd/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

The bootstrap will:
1. Detect OS (macOS / Arch)
2. Optionally install packages (Homebrew or yay)
3. Install oh-my-fish, fisher, tmux plugin manager
4. Symlink `home/benk/` into `$HOME`
5. Optionally copy `etc/` to `/etc` (prompted)

Existing files are backed up to `~/dotfiles.bak/`.
