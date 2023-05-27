# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="bira"

plugins=(git fancy-ctrl-z fzf)

source $ZSH/oh-my-zsh.sh

# aliases
alias v=nvim

export VISUAL=nvim;
export EDITOR=nvim;

alias l="exa -lagF --icons --git"
alias ll="exa -lagF --icons --git"
alias la="exa -lagF --icons --git"
alias ls="exa"
#eval $(thefuck --alias)

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export PATH=$PATH:$HOME/.local/bin/
export PATH=$PATH:$HOME/.cargo/env/
export MAKEFLAGS="-j$(nproc)"

source $HOME/.zshrc.local

