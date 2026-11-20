# dotfiles

How my machines should be set up. Two variables, handled differently:

- **Trust** is a *ladder*. `work` ⊂ `personal`: each level adds a layer on top of the one below.
- **OS** is a *filter*. It adds OS-specific variants on top.

```
dotfiles/
  dot                   launcher — symlink to ~/.local/bin/dot and run `dot` anywhere
  dot.py                the manager
  profiles.toml         the trust ladder and the profiles
  home/<layer>/         mirrors $HOME
  etc/<layer>/          mirrors /etc (Linux only, applied with sudo)
  packages/             brew.txt, brew-casks.txt, arch.txt — new-machine setup, split by OS only
  setup.toml            fish + tmux plugins
  themes/               submodules
```

## layers

A layer is a directory named `<level>` or `<level>@<os>` (os = `macos`, `linux`, `arch`). A machine applies, for every level it's trusted with, `<level>` then `<level>@<os>`. Later layers override earlier ones.

| machine      | layers applied                                                          |
|--------------|-------------------------------------------------------------------------|
| work Mac     | `common`, `common@macos`                                                |
| personal Mac | `common`, `common@macos`, `personal`, `personal@macos`                  |
| Arch PC      | `common`, `common@linux`, `common@arch`, `personal`, `personal@linux`, `personal@arch` |

```
home/common/            nvim, fish, ghostty, zed, tmux, vim, rex → every machine
home/personal/          zshrc, btop, kitty, wallpapers, ssh      → personal machines
home/personal@linux/    i3, polybar, awesome, rofi, wezterm ...  → my Linux PC
home/personal@macos/    iTerm2 prefs                             → personal Mac
etc/personal@linux/     fstab, nginx                             → my Linux PC
```

Only layers that exist matter. A file in a layer your machine doesn't apply **never reaches it**, so new files fail closed. Typo'd layer names are ignored with a warning.

**Per-OS differences without templates:** prefer configs that adapt at runtime (tmux `if-shell`, wezterm Lua, ghostty's fish-finding `command`). Otherwise put the OS bit in an OS layer — as a `conf.d/` drop-in, an include file (ghostty's `config-file = ?config.local`), or the same path overriding the generic one.

## setup

```bash
git clone --recurse-submodules git@github.com:benkyd/dotfiles.git ~/dotfiles
ln -s ~/dotfiles/dot ~/.local/bin/dot
dot
```

`dot` keeps a private venv (`~/.local/share/dotfiles/venv`), so it works regardless of the system Python or an active venv. First run asks what kind of machine this is (`work` / `personal`) and saves it to `~/dotfiles/.machine` — gitignored, so each machine keeps its own. Change it any time with `dot profile`; switching never deletes files.

## usage

```bash
dot                         # interactive menu
dot sync                    # git pull, then sync both ways — the everyday command
dot status                  # what differs (changes nothing)
dot diff [path...]          # exactly what differs
dot apply                   # repo → machine only   (alias: copy)
dot save                    # machine → repo only   (alias: pull)
dot install                 # new machine: packages → dotfiles → shell tooling
dot profile [work|personal]
dot add [--to LAYER] ~/.config/foo     # start tracking; default layer = highest trust (fail closed)
dot move ~/.config/foo common          # promote/demote between layers (git mv)
```

`~/.dotignore` adds per-machine exclusions (gitignore-style, paths relative to `$HOME`).

## how sync decides what's newer

Not by timestamps — git stamps everything "now". Files are compared by content against the version last synced on this machine (`~/.local/state/dotfiles/state.json`):

- only the repo changed → deployed
- only this machine changed → saved into the repo (into whichever layer provides the file)
- both changed → you choose: view the diff, take either side, or merge in `nvim -d`

On a machine with no sync state, a file matching any version in its git history counts as "repo is newer"; anything else asks. Non-interactive runs never guess — they skip and list what needs a decision. Anything overwritten is backed up to `~/dotfiles.bak/<timestamp>/`.
