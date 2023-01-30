#!bin/bash

# Install the packages that the dotfiles need to function properly

# Dev utils
yay -S neovim-git nvm neovim kitty ranger ripgrep

# Manjaro/i3 visuals with Yay
yay -S ttf-twemoji xotf-nerd-fonts-monacob-mono xidlehook sysstat i3blocks mpris-ctl flameshot perl rofi

mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
curl -fLo "Droid Sans Mono for Powerline Nerd Font Complete.otf" https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/DroidSansMono/complete/Droid%20Sans%20Mono%20Nerd%20Font%20Complete.otf 
cd ~

# Tmux
yay -S tmux
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux source ~/.tmux.conf

# Manjaro/i3 audio with Yay
yay -S pulseaudio-equalizer-ladspa mpris-ctl

