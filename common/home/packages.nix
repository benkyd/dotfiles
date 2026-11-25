# Tools every machine gets. Each app's own needs (language servers etc.) are in
# its programs/<app>/default.nix instead.
{ pkgs, lib, ... }:
{
  home.packages =
    with pkgs;
    [
      git
      curl
      wget
      rsync
      ripgrep
      fd
      eza
      btop
      fastfetch

      # languages and build tools
      cmake
      rustc
      cargo
      nodejs
      python3
    ]
    ++ lib.optionals stdenv.isLinux [
      wl-clipboard # bin/clip
      xclip
      lldb
      gcc
    ];
}
