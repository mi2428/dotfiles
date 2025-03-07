export DENO_INSTALL=$HOME/.deno
export CARGO_HOME="$HOME/.cargo"
export VOLTA_HOME="$HOME/.volta"
export FZF_HOME="$HOME/.fzf"
typeset -U path PATH
path=(
  $HOME/bin
  $HOME/dotfiles/bin
  $HOME/.local/bin
  $DENO_INSTALL/bin
  $CARGO_HOME/bin
  $VOLTA_HOME/bin
  $FZF_HOME/bin
  /usr/bin
  /usr/sbin
  /bin
  /sbin
  /snap/bin
  /usr/local/bin
  /usr/local/sbin
  .
)

export GOPATH="$HOME/io/gocode"
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=$HOME/.local/share/zsh/zsh-syntax-highlighting/highlighters
source $HOME/.local/share/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source $HOME/.local/share/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
