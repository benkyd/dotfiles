{ pkgs, lib, link, ... }:
{
  # Linux gets Ghostty from nixpkgs (on Arch it needs nixGL for the GPU);
  # nixpkgs doesn't build it for macOS, so there it stays the Homebrew cask
  home.packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.ghostty ];

  xdg.configFile = {
    "ghostty/config".source = link "common/home/programs/ghostty/config";
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    # config includes this with `config-file = ?config.local`
    "ghostty/config.local".source = link "common/home/programs/ghostty/macos.conf";
  };
}
