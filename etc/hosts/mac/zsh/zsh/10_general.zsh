setopt BANG_HIST
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt ALWAYS_TO_END
setopt NO_BEEP
setopt AUTO_CD
setopt AUTOPUSHD
setopt PUSHD_IGNORE_DUPS
setopt CORRECT
setopt MAGIC_EQUAL_SUBST
setopt PROMPT_SUBST
setopt NOTIFY
setopt AUTO_LIST
setopt AUTO_MENU
setopt LIST_PACKED
setopt LIST_TYPES
setopt NO_LIST_BEEP
setopt IGNORE_EOF
setopt NO_AUTOREMOVESLASH
setopt NONOMATCH

export HISTSIZE=1000000
export SAVEHIST=1000000
export HISTFILE=$HOME/.zhistory

export TERM=xterm-256color
#export TERM=screen-256color

#export LANG=ja_JP.UTF-8
#export LC_CTYPE=ja_JP.UTF-8
export LANG=en_JP.UTF-8
export LC_CTYPE=en_JP.UTF-8

export FPATH=/opt/homebrew/share/zsh-completions:$FPATH
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=/opt/homebrew/share/zsh-syntax-highlighting/highlighters
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/opt/zsh-git-prompt/zshrc.sh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source $HOME/.fzf.zsh

autoload -Uz colors && colors
autoload -Uz compinit && compinit

zstyle ':completion:*'              matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*'              verbose yes
zstyle ':completion:*'              completer _expand _complete _match _prefix _approximate _list _history
zstyle ':completion:*'              group-name ''
zstyle ':completion:*'              list-separator '-->'
zstyle ':completion:*:commands'     rehash 1
zstyle ':completion:*:default'      menu select=2
zstyle ':completion:*:options'      description 'yes'
zstyle ':completion:*:messages'     format '%F{YELLOW}%d'$DEFAULT
zstyle ':completion:*:warnings'     format '%F{RED}No matches for:''%F{YELLOW} %d'$DEFAULT
zstyle ':completion:*:descriptions' format '%F{YELLOW}completing %B%d%b'$DEFAULT
zstyle ':completion:*:descriptions' format '%F{yellow}Completing %B%d%b%f'$DEFAULT
zstyle ':completion:*:manuals'      separate-sections true
zstyle ':completion:*:sudo:*'       command-path $path


if [[ -d ~/.ssh ]]; then
  local h=()
  if [[ -r ~/.ssh/config ]]; then
    h=($h ${${${(@M)${(f)"$(cat ~/.ssh/config)"}:#Host *}#Host }:#*[*?]*})
  fi
  if [[ -r ~/.ssh/known_hosts ]]; then
    h=($h ${${${(f)"$(cat ~/.ssh/known_hosts{,2} || true)"}%%\ *}%%,*}) 2>/dev/null
  fi
  if [[ $#h -gt 0 ]]; then
    zstyle ':completion:*:ssh:*' hosts $h
    zstyle ':completion:*:scp:*' hosts $h
    zstyle ':completion:*:slogin:*' hosts $h
  fi
fi


export EDITOR="vi"
bindkey -e  # set explicitly, or zsh use vi-mode binding
bindkey '^O' autosuggest-accept


case $(arch) in
x86_64)
  export VOLTA_HOME="$HOME/.volta_x64"
  typeset -U path PATH
  path=(
    $HOME/bin
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
  export CARGO_HOME="$HOME/.cargo"
  export VOLTA_HOME="$HOME/.volta"
  typeset -U path PATH
  path=(
    $HOME/bin
    $CARGO_HOME/bin
    $VOLTA_HOME/bin
    /opt/homebrew/bin(N-/)
    /opt/homebrew/sbin(N-/)
    /usr/bin
    /usr/sbin
    /bin
    /sbin
    /usr/local/bin
    /usr/local/sbin
    /Library/Apple/usr/bin
  )
  ;;
esac


export GOPATH="$HOME/dev/gocode"


if [[ -n ${SSH_AGENT_PID} ]] && ! ssh-add -l 1> /dev/null; then
  ssh-add $HOME/.ssh/MASTER_KEY/mi2428.master.id_ed25519
  echo
fi


REPORTTIME=30
TIMEFMT='JOB:  %J
TIME: %E (user: %U, kernel: %S)
CPU:  %P'
