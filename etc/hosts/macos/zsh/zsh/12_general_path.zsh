case $(arch) in
x86_64)
  export VOLTA_HOME="$HOME/.volta_x64"
  typeset -U path PATH
  path=(
    $HOME/bin
    $HOME/dotfiles/bin
    $HOME/.local/bin
    $VOLTA_HOME/bin
    /usr/local/bin(N-/)   # use /usr/local/bin in preference to /usr/bin in Intel Mac
    /usr/local/sbin(N-/)  # use /usr/local/sbin in preference to /usr/sbin in Intel Mac
    /usr/bin
    /usr/sbin
    /bin
    /sbin
    /Library/Apple/usr/bin
  )
  ;;
arm64*)
  export DENO_INSTALL=$HOME/.deno
  export CARGO_HOME="$HOME/.cargo"
  export VOLTA_HOME="$HOME/.volta"
  export TEXLIVE_BIN="/usr/local/texlive/2021/bin/universal-darwin"
  export FZF_BIN="/opt/homebrew/opt/fzf/bin"
  typeset -U path PATH
  path=(
    $HOME/bin
    $HOME/dotfiles/bin
    $HOME/.local/bin
    $DENO_INSTALL/bin
    $CARGO_HOME/bin
    $VOLTA_HOME/bin
    $TEXLIVE_BIN
    $FZF_BIN
    /opt/homebrew/bin(N-/)
    /opt/homebrew/sbin(N-/)
    /usr/local/bin
    /usr/local/sbin
    /usr/bin
    /usr/sbin
    /bin
    /sbin
    /Library/Apple/usr/bin
    .
  )
  ;;
esac

export GOPATH="$HOME/dev/gocode"
export FPATH=/opt/homebrew/share/zsh-completions:$FPATH
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=/opt/homebrew/share/zsh-syntax-highlighting/highlighters
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/opt/zsh-git-prompt/zshrc.sh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
