export DENO_INSTALL=$HOME/.deno
export CARGO_HOME=$HOME/.cargo
export GOPATH="$HOME/io/gocode"
export GOPRIVATE=github.com/soracom

case $(arch) in
x86_64|i386)
  export HOMEBREW_HOME=/usr/local
  export VOLTA_HOME=$HOME/.volta_x64
  export FZF_BIN=$HOMEBREW_HOME/opt/fzf/bin
  typeset -U path PATH
  path=(
    $HOME/bin
    $HOME/io/bin
    $HOME/dotfiles/bin
    $HOME/.local/bin
    $GOPATH/bin
    $DENO_INSTALL/bin
    $CARGO_HOME/bin
    $VOLTA_HOME/bin
    $HOMEBREW_HOME/bin(N-/)   # use /usr/local/bin in preference to /usr/bin in Intel Mac
    $HOMEBREW_HOME/sbin(N-/)  # use /usr/local/sbin in preference to /usr/sbin in Intel Mac
    /usr/bin
    /usr/sbin
    /bin
    /sbin
    /Library/Apple/usr/bin
    .
    ./bin
  )
  ;;
arm64*)
  export HOMEBREW_HOME=/opt/homebrew
  export VOLTA_HOME="$HOME/.volta"
  export TEXLIVE_BIN=/usr/local/texlive/2022/bin/universal-darwin
  export FZF_BIN=$HOMEBREW_HOME/opt/fzf/bin
  #export RANCHER_DESKTOP_BIN="$HOME/.rd/bin"
  typeset -U path PATH
  path=(
    $HOME/bin
    $HOME/io/bin
    $HOME/dotfiles/bin
    $HOME/.local/bin
    $GOPATH/bin
    $DENO_INSTALL/bin
    $CARGO_HOME/bin
    $VOLTA_HOME/bin
    $TEXLIVE_BIN
    $FZF_BIN
    $RANCHER_DESKTOP_BIN
    $HOMEBREW_HOME/bin(N-/)
    $HOMEBREW_HOME/sbin(N-/)
    $HOMEBREW_HOME/opt/postgresql@13/bin
    $HOMEBREW_HOME/opt/postgresql@14/bin
    $HOMEBREW_HOME/opt/postgresql@15/bin
    /usr/local/bin
    /usr/local/sbin
    /usr/bin
    /usr/sbin
    /bin
    /sbin
    /Library/Apple/usr/bin
    .
    ./bin
  )
  ;;
esac

export FPATH=$HOMEBREW_HOME/share/zsh-completions:$FPATH
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=$HOMEBREW_HOME/share/zsh-syntax-highlighting/highlighters
source $HOMEBREW_HOME/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source $HOMEBREW_HOME/opt/zsh-git-prompt/zshrc.sh
source $HOMEBREW_HOME/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

if whence -p rbenv 1>/dev/null; then
  eval "$(rbenv init - zsh)"
fi

if whence -p nodenv 1>/dev/null; then
  eval "$(nodenv init - zsh)"
fi

if whence -p direnv 1>/dev/null; then
  eval "$(direnv hook zsh)"
fi

