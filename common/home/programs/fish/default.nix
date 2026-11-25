{ pkgs, link, ... }:
{
  home.packages = [ pkgs.fish ];

  # Only config.fish: fish writes fish_variables, completions etc. into the
  # folder. Machine-only lines go in ~/.config/fish/local.fish (never in git).
  xdg.configFile."fish/config.fish".source = link "common/home/programs/fish/config.fish";
}
