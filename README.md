# dotfiles

The same editor, shell and terminal on every machine: Neovim, fish, tmux,
vim, Ghostty and Rex, set up with Nix (flakes + home-manager). The old `dot`
setup, and i3, polybar, kitty and friends, live on the `legacy` branch.

```
flake.nix                      inputs, plus one entry per machine
systems/<host>/home.nix        only what differs on that machine (user, home folder)
common/home/default.nix        what every machine gets
common/home/packages.nix       everyday tools
common/home/programs/<app>/    one folder per app: default.nix installs it and links
                               its config files, which sit next to it
common/home/bin/clip
```

Configs are **linked** to this checkout, not copied, so it must live at
`~/dotfiles`. Edit them here and they apply at once; rebuild only when packages
or links change. Nix only sees files git knows about, so `git add` new ones.

```sh
home-manager switch --flake ~/dotfiles                          # after changing packages or links
nix flake update --flake ~/dotfiles && home-manager switch --flake ~/dotfiles   # update everything
```

Machine-only settings never go in git: fish reads `~/.config/fish/local.fish`.

## Plan

Status: skeleton written on the work Mac (`benk-studio`); nothing built yet.

Every step can be undone. Building changes nothing on the machine; only
`switch` does, and `-b backup` moves existing files aside as `*.backup`.
`home-manager uninstall` removes the links again, and
`/nix/nix-installer uninstall` removes Nix completely.

### 1. This Mac (benk-studio)

1. Install Nix and open a new shell:
   `curl -fsSL https://install.determinate.systems/nix | sh -s -- install`
2. `git -C ~/dotfiles switch nix`. The configs here are dot's copies, so
   nothing changes yet.
3. Build, then look in `result/home-files/` to see every link it would make:
   `nix build ~/dotfiles#homeConfigurations.benk@benk-studio.activationPackage`
   Fix any package names that fail (see the TODO in `programs/neovim`), then
   commit the new `flake.lock`.
4. Put the work lines from today's `~/.config/fish/config.fish` (agxgittools
   on PATH, the agx venv) in `~/.config/fish/local.fish`.
5. Switch: `nix run home-manager/master -- switch --flake ~/dotfiles -b backup`.
   `~/.config/nvim` moves to `~/.config/nvim.backup`; its `.claude/` folder is
   in there.
6. Check, in a new shell: `which nvim tmux rg` should be in `~/.nix-profile/bin`;
   then Neovim, tmux, Ghostty and Rex.
7. Remove the Homebrew formulae Nix now provides (keep the casks) and the
   `~/.local/bin/dot` link.

### 2. Linux PC (another agent can do this)

1. Install Nix with the same command, clone this repo to `~/dotfiles`, `git switch nix`.
2. Add `systems/<hostname>/home.nix` (copy benk-studio's: username,
   `/home/<user>`) and a line in `flake.nix`:
   `"<user>@<hostname>" = machine "x86_64-linux" ./systems/<hostname>/home.nix;`
   `git add` both.
3. Build as in step 1.3.
4. Try it on a throwaway user first: `sudo useradd -m nixtest`, clone into its
   home and switch there. Then switch your own user with `-b backup`.
5. Ghostty from nixpkgs needs nixGL on Arch; either set that up or keep
   pacman's Ghostty and leave it out for this host. Remove the pacman packages
   Nix now provides.

### Later

- Personal Mac: same as step 1.
- nix-darwin on the Macs, for Homebrew casks, macOS settings and the login
  shell (fish stays Homebrew's until then). With Nix from the Determinate
  installer, nix-darwin needs `nix.enable = false`.
- NixOS on the Linux PC; try it first with `nixos-rebuild build-vm`.
- Nix installs the Neovim plugins instead of lazy.nvim. hardline, fsplash and
  fyler aren't in nixpkgs and would need building from GitHub.

### Notes

- fish: `config.fish` moves Nix's folders ahead of Homebrew and the universal
  `fish_user_paths`, so Nix's tools win.
- clang-tools from Nix replaces Homebrew's `clangd` and `clang-format` on PATH.
  Neovim still prefers the work clangd wrapper in `~/bin`; update its path in
  `nvim/lua/lsp.lua` when that moves to the workbin.
