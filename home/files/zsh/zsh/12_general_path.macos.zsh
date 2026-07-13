source $HOME/.envs  # set secret envs like GOOGLE_CLOUD_PROJECT

case $(arch) in
x86_64|i386)
  export HOMEBREW_HOME=/usr/local
  export VOLTA_HOME=$HOME/.volta_x64
  export FZF_BIN=$HOMEBREW_HOME/opt/fzf/bin
  ;;
arm64*)
  export HOMEBREW_HOME=/opt/homebrew
  export VOLTA_HOME="$HOME/.volta"
  export TEXLIVE_BIN=/usr/local/texlive/2022/bin/universal-darwin
  export FZF_BIN=$HOMEBREW_HOME/opt/fzf/bin
  #export RANCHER_DESKTOP_BIN="$HOME/.rd/bin"
  ;;
esac

if whence -p rbenv 1>/dev/null; then
  eval "$(rbenv init - zsh)"
fi

if whence -p nodenv 1>/dev/null; then
  eval "$(nodenv init - zsh)"
fi

if whence -p direnv 1>/dev/null; then
  eval "$(direnv hook zsh)"
fi
