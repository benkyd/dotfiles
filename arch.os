#!/bin/bash
#
# Dev utilsv
yay -S neovim-git nvm wezterm ranger ripgrep zsh zsh-vi-mode curl exa
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# WM Deps
yay -S awesome-git
yay -S picom-pijulis-git
yay -S i3exit arc-icon-theme ttf-twemoji xorg-xbacklight xidlehook sysstat i3blocks mpris-ctl flameshot perl rofi

mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
curl -fLo "Droid Sans Mono for Powerline Nerd Font Complete.otf" https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/DroidSansMono/complete/Droid%20Sans%20Mono%20Nerd%20Font%20Complete.otf
cd ~

# Tmux
yay -S tmux
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux source ~/.tmux.conf

git clone https://gist.github.com/fa6258f3ff7b17747ee3.git
cd ./fa6258f3ff7b17747ee3
chmod +x sp
# This widget will work by default if the binary is in the system PATH
sudo cp ./sp /usr/local/bin/

# Audio
yay -S pulseaudio-equalizer-ladspa mpris-ctl

