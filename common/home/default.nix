# The setup every machine shares. Each app has a folder in programs/ holding
# its config files and a default.nix that installs it and links them.
{ config, lib, ... }:
{
  imports = [
    ./packages.nix
    ./programs/neovim
    ./programs/fish
    ./programs/ghostty
    ./programs/rex
    ./programs/tmux
    ./programs/vim
  ];

  options.dotfiles.root = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/dotfiles";
    description = "Where this repo is checked out. Configs are linked to it, so edits apply at once.";
  };

  config = {
    # `link "common/home/..."` points a file in $HOME straight at the file in
    # the repo checkout (not a copy in /nix/store), so edits apply without a rebuild
    _module.args.link = path: config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.root}/${path}";

    home.file."bin/clip".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.root}/common/home/bin/clip";

    programs.home-manager.enable = true; # installs the home-manager command
    home.stateVersion = "26.05"; # leave as is; it's not the version of anything installed
  };
}
