export DENO_INSTALL="$HOME/.deno"
export CARGO_HOME="$HOME/.cargo"
export GOPATH="$HOME/io/gocode"
export GOPRIVATE=github.com/soracom

[[ -r "$HOME/.envs" ]] && source "$HOME/.envs"  # secret envs like GOOGLE_CLOUD_PROJECT

case $(arch) in
x86_64|i386)
  export HOMEBREW_HOME="/usr/local"
  export VOLTA_HOME="$HOME/.volta_x64"
  typeset -U path PATH
  path=(
    $HOME/bin
    $HOME/dotfiles/bin
    $HOME/io/bin
    $HOME/.nix-profile/bin
    /run/current-system/sw/bin
    /nix/var/nix/profiles/default/bin
    $HOME/.local/bin
    $GOPATH/bin
    $DENO_INSTALL/bin
    $CARGO_HOME/bin
    $VOLTA_HOME/bin
    $HOMEBREW_HOME/bin(N-/)   # use /usr/local/bin in preference to /usr/bin in Intel Mac
    $HOMEBREW_HOME/sbin(N-/)  # keep Homebrew taps available on Intel Mac
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
  export HOMEBREW_HOME="/opt/homebrew"
  export VOLTA_HOME="$HOME/.volta"
  export TEXLIVE_BIN=/usr/local/texlive/2022/bin/universal-darwin
  #export RANCHER_DESKTOP_BIN="$HOME/.rd/bin"
  typeset -U path PATH
  path=(
    $HOME/bin
    $HOME/dotfiles/bin
    $HOME/io/bin
    $HOME/.nix-profile/bin
    /run/current-system/sw/bin
    /nix/var/nix/profiles/default/bin
    $HOME/.local/bin
    $GOPATH/bin
    $DENO_INSTALL/bin
    $CARGO_HOME/bin
    $VOLTA_HOME/bin
    $TEXLIVE_BIN
    $RANCHER_DESKTOP_BIN
    $HOMEBREW_HOME/bin(N-/)
    $HOMEBREW_HOME/sbin(N-/)
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

export FPATH="$HOME/.local/share/zsh/site-functions:$FPATH"
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR="$HOME/.local/share/zsh/zsh-syntax-highlighting/highlighters"
[[ -r "$HOME/.local/share/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] \
  && source "$HOME/.local/share/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -r "$HOMEBREW_HOME/opt/zsh-git-prompt/zshrc.sh" ]] \
  && source "$HOMEBREW_HOME/opt/zsh-git-prompt/zshrc.sh"
[[ -r "$HOME/.local/share/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] \
  && source "$HOME/.local/share/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

if whence -p rbenv 1>/dev/null; then
  eval "$(rbenv init - zsh)"
fi

if whence -p nodenv 1>/dev/null; then
  eval "$(nodenv init - zsh)"
fi

if whence -p direnv 1>/dev/null; then
  eval "$(direnv hook zsh)"
fi
