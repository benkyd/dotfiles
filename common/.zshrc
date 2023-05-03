# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="bira"

plugins=(git fancy-ctrl-z fzf)

source $ZSH/oh-my-zsh.sh

# more based keybinginds for regular ass typing
source /usr/share/zsh/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh
ZVM_VI_EDITOR=vim

# aliases

alias vim=nvim
alias vi=nvim
alias v=nvim
alias oldvim=vim

export VISUAL=nvim;
export EDITOR=nvim;

alias l="exa -lagF --icons --git"
alias ll="exa -lagF --icons --git"
alias la="exa -lagF --icons --git"
alias ls="exa"
#eval $(thefuck --alias)

#[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

source $HOME/.zshrc.local

