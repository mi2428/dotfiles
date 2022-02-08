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

export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_TERMINAL=iTerm2

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
  export TEXLIVE_BIN="/usr/local/texlive/2021/bin/universal-darwin"
  export FZF_BIN="/opt/homebrew/opt/fzf/bin"
  typeset -U path PATH
  path=(
    $HOME/bin
    $CARGO_HOME/bin
    $VOLTA_HOME/bin
    $TEXLIVE_BIN
    $FZF_BIN
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
export FPATH=/opt/homebrew/share/zsh-completions:$FPATH
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=/opt/homebrew/share/zsh-syntax-highlighting/highlighters
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/opt/zsh-git-prompt/zshrc.sh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

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
bindkey -e  # set explicitly, or zsh use vi-mode binding by default
bindkey '^O' autosuggest-accept


backward-kill-dir() {
  local WORDCHARS=${WORDCHARS/\/}
  zle backward-kill-word
}
zle -N backward-kill-dir
bindkey '^W' backward-kill-dir  # remap


if [[ -n ${SSH_AGENT_PID} ]] && ! ssh-add -l 1> /dev/null; then
  ssh-add $HOME/.ssh/MASTER_KEY/mi2428.master.id_ed25519
  echo
fi


REPORTTIME=300
TIMEFMT='JOB:  %J
TIME: %E (user: %U, kernel: %S)
CPU:  %P'


source /opt/homebrew/opt/fzf/shell/completion.zsh
source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
export FZF_COMPLETION_TRIGGER='**'
export FZF_DEFAULT_COMMAND="fd"
export FZF_DEFAULT_OPTS='--height 60% --border --inline-info --preview-window=right:60%:wrap --color=fg:252,fg+:233,bg+:002,preview-fg:252,prompt:226,pointer:007,info:247,spinner:011,header:009,gutter:237,hl:220,hl+:231'
export FZF_COMPLETION_OPTS="${FZF_DEFAULT_OPTS}"
export FZF_TMUX=1
export FZF_TMUX_HEIGHT=20

# Use fd (https://github.com/sharkdp/fd) instead of the default find
# command for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
  fd --hidden --follow --exclude ".git" . "$1"
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fd --type d --hidden --follow --exclude ".git" . "$1"
}

# (EXPERIMENTAL) Advanced customization of fzf options via _fzf_comprun function
# - The first argument to the function is the name of the command.
# - You should make sure to pass the rest of the arguments to fzf.
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
    cd|pushd)     fzf "$@" --preview 'tree -L 3 -C {} | head -200' ;;
    vi|vim|nvim)  fzf "$@" --preview '[[ $(file --mime {}) =~ directory ]] \
                                      && tree -L 3 -C {} | head -200 \
                                      || bat --style=numbers --color=always --line-range :500 {}' ;;
    cot|code)     fzf "$@" --preview '[[ $(file --mime {}) =~ directory ]] \
                                      && tree -L 3 -C {} | head -200 \
                                      || bat --style=numbers --color=always --line-range :500 {}' ;;
    export|unset) fzf "$@" --preview "eval 'echo \$'{}" ;;
    ssh)          fzf "$@" --preview 'curl -s https://ipinfo.io/{} | bat -l json --color=always' ;;
    *)            fzf "$@" ;;
  esac
}
