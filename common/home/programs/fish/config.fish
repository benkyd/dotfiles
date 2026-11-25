if test -d /opt/homebrew/bin
    fish_add_path /opt/homebrew/bin/
end

# Rex CLI
set -l rex_dir "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
if test -d $rex_dir
    fish_add_path -a $rex_dir
end

# Nix's tools come first, ahead of Homebrew and fish_user_paths
# (fish_add_path skips folders that don't exist, so this is harmless without Nix)
fish_add_path --path --move ~/.nix-profile/bin /nix/var/nix/profiles/default/bin

if status is-interactive
    alias v 'nvim'
end

# Lines for this machine only (e.g. work paths); never in git
if test -f ~/.config/fish/local.fish
    source ~/.config/fish/local.fish
end
