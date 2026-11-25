{ pkgs, link, ... }:
{
  home.packages = [ pkgs.vim ];
  # Neovim sources this too (nvim/init.lua)
  home.file.".vimrc".source = link "common/home/programs/vim/vimrc";
}
