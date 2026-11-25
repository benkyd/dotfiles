{ pkgs, lib, link, ... }:
let
  rex = file: link "common/home/programs/rex/${file}";
in
{
  # Rex itself is installed outside Nix. File by file, so anything Rex keeps
  # in ~/.config/rex stays put.
  xdg.configFile = {
    "rex/init.lua".source = rex "init.lua";
    "rex/choose-tree-watcher.lua".source = rex "choose-tree-watcher.lua";
    "rex/choose-tree.c".source = rex "choose-tree.c";
    "rex/themes".source = rex "themes";
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    "rex/local.lua".source = rex "macos.lua";
  };
}
