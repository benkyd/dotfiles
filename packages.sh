#!bin/bash

# Install the packages that the dotfiles need to function properly

# Dev utils
yay -S nvm

# Manjaro/i3 visuals with Yay
yay -S ttf-twemoji xidlehook sysstat i3blocks mpris-ctl flameshot perl

# Manjaro/i3 audio with Yay
yay -S pulseaudio-equalizer-ladspa mpris-ctl
