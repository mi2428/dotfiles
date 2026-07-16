export DENO_INSTALL=$HOME/.deno
export CARGO_HOME="$HOME/.cargo"
export VOLTA_HOME="$HOME/.volta"
typeset -U path PATH
path=(
  $HOME/bin
  $HOME/.nix-profile/bin
  /run/current-system/sw/bin
  /nix/var/nix/profiles/default/bin
  $HOME/.local/bin
  $DENO_INSTALL/bin
  $CARGO_HOME/bin
  $VOLTA_HOME/bin
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
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=${CTP_OVERLAY0}"
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=$HOME/.local/share/zsh/zsh-syntax-highlighting/highlighters
[[ -r "$HOME/.local/share/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] \
  && source "$HOME/.local/share/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -r "$HOME/.local/share/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] \
  && source "$HOME/.local/share/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

if whence -p mise 1>/dev/null; then
  eval "$(mise activate zsh)"
fi
