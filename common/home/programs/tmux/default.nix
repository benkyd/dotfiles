{ pkgs, link, ... }:
{
  home.packages = [ pkgs.tmux ];
  home.file.".tmux.conf".source = link "common/home/programs/tmux/tmux.conf";
}
