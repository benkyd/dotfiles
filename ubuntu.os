#!/bin/bash
# Dev utils
sudo apt install neovim kitty ranger ripgrep curl zsh
curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

yay -S flameshot
git clone --filter=blob:none --sparse git@github.com:ryanoasis/nerd-fonts
source nerdfonts/install.sh

sudo apt update

mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
curl -fLo "Droid Sans Mono for Powerline Nerd Font Complete.otf" https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/DroidSansMono/complete/Droid%20Sans%20Mono%20Nerd%20Font%20Complete.otf 
cd ~

# Tmux
sudo apt install tmux
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux source ~/.tmux.conf
