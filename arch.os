#!/bin/bash
#
# Dev utilsv
yay -S neovim-git nvm wezterm ranger ripgrep zsh zsh-vi-mode curl exa
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# WM Deps
yay -S awesome-git i3 betterlockscreen polybar-git eww xss-lock ttf-material-design-icons ttf-unifont polybar
yay -S picom-ftlabs-git dunst alternating-layouts-git
yay -S i3exit arc-icon-theme ttf-twemoji xorg-xbacklight xidlehook sysstat i3blocks mpris-ctl flameshot perl rofi
yay -S ttf-dejavu-nerd

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

