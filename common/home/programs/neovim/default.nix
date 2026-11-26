{ pkgs, lib, link, ... }:
{
  home.packages =
    with pkgs;
    [
      neovim
      tree-sitter # nvim-treesitter builds parsers with it
      ripgrep # telescope
      fd

      # language servers, enabled in nvim/lua/lsp.lua (rust-analyzer via rustaceanvim)
      clang-tools # clangd; the work Mac prefers ~/bin/clangd when it exists
      zls
      zig
      rust-analyzer
      lua-language-server
      pyright
      bash-language-server
      cmake-language-server
      vscode-langservers-extracted # jsonls, cssls, html
      typescript-language-server
      typescript

      # formatters, used by conform (<leader>F)
      stylua
      black
      prettier
    ]
    ++ lib.optionals stdenv.isLinux [ gcc ]; # parsers need a C compiler; macOS uses Xcode's

  # The whole folder: lazy.nvim installs plugins and keeps nvim/lazy-lock.json
  # (committed) up to date
  xdg.configFile."nvim".source = link "common/home/programs/neovim/nvim";
}
