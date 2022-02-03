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

export FPATH=/opt/homebrew/share/zsh-completions:$FPATH
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

bindkey '^O' autosuggest-accept


case $(arch) in
x86_64)
  export VOLTA_HOME="$HOME/.volta_x64"
  typeset -U path PATH
  path=(
    $HOME/bin
    $VOLTA_HOME/bin
    /usr/local/bin(N-/)   # use /usr/local/bin in preference to /usr/bin
    /usr/local/sbin(N-/)  # use /usr/local/sbin in preference to /usr/sbin
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










man() {
  # env PAGER="most -s" man $@
  env \
    LESS_TERMCAP_mb=$(printf "\e[1;31m") \
    LESS_TERMCAP_md=$(printf "\e[1;31m") \
    LESS_TERMCAP_me=$(printf "\e[0m") \
    LESS_TERMCAP_se=$(printf "\e[0m") \
    LESS_TERMCAP_so=$(printf "\e[0;0;102m") \
    LESS_TERMCAP_ue=$(printf "\e[0m") \
    LESS_TERMCAP_us=$(printf "\e[4;32m") \
    PAGER=/usr/bin/less \
    _NROFF_U=1 \
    PATH=${HOME}/bin:${PATH} \
  man "$@"
}




cd() {
  if whence -p exa 1> /dev/null; then
    builtin cd $1 && EXA_ICON_SPACING=1 exa --icons .
  else
    builtin cd $1 && ls --color=auto .
  fi
}


mcd() {
  mkdir -p $1 && pushd $1
}


tgz() {
  env COPYFILE_DISABLE=1 tar zcvf $1 --exclude=".DS_Store" ${@:2}
}


f() {
  open -a Finder ${$1:-'.'}
}


xx() {
  case $1 in
    *.tar.gz|*.tgz) tar xzvf $1;;
    *.tar.xz) tar Jxvf $1;;
    *.zip) unzip $1;;
    *.lzh) lha e $1;;
    *.tar.bz2|*.tbz) tar xjvf $1;;
    *.tar.Z) tar zxvf $1;;
    *.gz) gzip -d $1;;
    *.bz2) bzip2 -dc $1;;
    *.Z) uncompress $1;;
    *.tar) tar xvf $1;;
    *.arj) unarj $1;;
  esac
}


colortest() {
  for c in {000..255}; do
    echo -n "\e[38;5;${c}m $c"
    (( $(($c%16)) == 15 )) && echo
  done
}


alias grep='grep -n --color=auto'
alias preview='open -a Preview'

alias -s py=python
alias -s jl=julia
alias -s {gz,tgz,zip,lzh,bz2,tbz,Z,tar,arj,xz}=xx
alias -s {png,jpg,bmp,PNG,JPG,BMP}=preview

alias -g C='| pbcopy'
alias -g H='| head'
alias -g T='| tail'
alias -g X='| xargs'

alias :q='exit'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ..2='cd ../..'
alias ..3='cd ../../..'
alias ..4='cd ../../../..'
alias ..5='cd ../../../../..'

alias c='pbcopy'
alias g='git'
alias m='move'
alias o='open'
alias p='ping'
alias r='rm -i'
alias s='sudo'
alias y='yes'

alias an='ansible'
alias dc='docker-compose'
alias dk='docker'
alias kc='kubectl'
alias pp='ping6'
alias ::='tmux'

alias mkd='mkdir -p'
alias :::='tmuxinator'


if (( $+commands[arch] )); then
  alias x64='exec arch -arch x86_64 "$SHELL"'
  alias a64='exec arch -arch arm64e "$SHELL"'
fi


if whence -p exa 1> /dev/null; then
  export EXA_ICON_SPACING=1
  alias l='exa --icons'
  alias ls='exa --icons'
  alias ll='exa -l --icons'
  alias la='exa -l -arbghi --git --icons'
  alias lr='exa -lR -arbghi --git -I .git --icons'
  alias lt='exa -lT -arbghi --git -I .git --icons'
  alias laa="exa -l -arbghi@ --git --icons"
else
  alias l='ls --color=auto'
  alias ls='ls --color=auto'
  alias ll='ls --color=auto -alF'
  alias la='ls --color=auto -A'
fi


if whence -p htop 1> /dev/null; then
  alias top='htop'
fi


if whence -p vim 1> /dev/null; then
  alias vi='vim'
  alias emacs='vim'
fi


if whence -p nvim 1> /dev/null; then
  alias vi='nvim'
  alias vim='nvim'
  alias emacs='nvim'
fi


if whence -p code 1> /dev/null; then
  alias edit='code'
  alias atom='code'
fi


if whence -p tldr 1> /dev/null; then
  alias h='tldr'
else
  alias h='man'
fi


if whence -p mplayer 1> /dev/null; then
  alias -s {mp3,mp4,wav,mkv,m4v,m4a,wmv,avi,mpeg,mpg,vob,mov,rm}='mplayer'
fi










git_prompt() {
  if [[ "$(git rev-parse --is-inside-work-tree 2> /dev/null)" == "true" ]]; then
    return 0
  else
    return 0
  fi
}


ssh_prompt() {
  if [[ -n $SSH_CLIENT ]]; then
    return 0
  else
    return 0
  fi
}


privileged_prompt() {
  if (( $EUID == 0 )); then
    return 0
  else
    return 0
  fi
}



typeset -gA PROMPT_SYMBOL=(
  corner.top     '╭─'
  corner.bottom  '╰─'
  arrow          '─▶'
  exit.success   '(๑˃̵ᴗ˂̵)و'
)


typeset -gA PROMPT_PALETTE=(
  host         '%b%F{157}'
  user         '%b%F{253}'
  path         '%B%F{228}'
  venv         '%b%F{081}'
  time         '%b%F{254}'
  elapsed      '%b%F{222}'
  exit.mark    '%b%F{246}'
  exit.code    '%B%F{203}'
  git.commited '%b%F{159}'
  git.staged   '%b%F{253}'
  git.modified '%b%F{253}'
  git.other    '%b%F{253}'
  conj         '%b%F{102}'
  typing       '%b%F{252}'
  normal       '%b%F{252}'
  success      '%b%F{040}'
  error        '%b%F{203}'
  reset        '%{\e[00m%}'
)


typeset -gA prompts=(
  margin   ""
  host     ""
  user     ""
  path     ""
  venv     ""
  git      ""
  time     ""
  elapsed  ""
  typing   ""
  exit     ""
)


typeset -gA prompts_len=(
  margin   0
  host     0
  user     0
  path     0
  venv     0
  git      0
  time     0
  elapsed  0
  exit     0
)


typeset -gi exec_timestamp=0


set_exec_timestamp() {
  exec_timestamp=$(date +%s)
}


set_margin() {
  if [[ -n $NEW_LINE_BEFORE_PROMPT ]] && (( LINES > 16 )); then
    prompts[margin]="${PROMPT_PALETTE[reset]}\n"
  else
    NEW_LINE_BEFORE_PROMPT=true
  fi
}


set_hostname() {
  local name=${(%):-%M}
  prompts[host]="${PROMPT_PALETTE[normal]}[${PROMPT_PALETTE[host]}${name}${PROMPT_PALETTE[normal]}]"
  prompts_len[host]=$(( ${#name} + 2 ))
}


set_user() {
  local user=${(%):-%n}
  local user_color=${PROMPT_PALETTE[user]}
  if (( $EUID == 0 )); then
    user_color=${PROMPT_PALETTE[root]}
  fi
  prompts[user]=" ${PROMPT_PALETTE[conj]}as ${user_color}${user}"
  prompts_len[user]=$(( ${#user} + 4 ))
}


set_current_path() {
  local current_path=${(%):-%~}
  prompts[path]=" ${PROMPT_PALETTE[conj]}in ${PROMPT_PALETTE[path]}${current_path}"
  prompts_len[path]=$(( ${#current_path} + 4 ))
}


set_elapsed_time() {
  if (( exec_timestamp > 0 )); then
    local exec_seconds=" +$(( $(date +%s) - exec_timestamp ))sec"
    prompts[elapsed]="${exec_seconds}"
    prompts_len[elapsed]=${#exec_seconds}
    exec_timestamp=0
  else
    prompts[elapsed]=""
    prompts_len[elapsed]=0
  fi
}


set_current_time() {
  local current_time=${(%):-%D{%H:%M:%S}}
  prompts[time]="${PROMPT_PALETTE[time]}${current_time}"
  prompts_len[time]=${#current_time}
}


set_git_info() {
  if [[ -d ${PWD}/.git ]]; then
    local git_status="$(git status 2> /dev/null)"
    local git_branch="${$(git branch --show-current 2> /dev/null):-???}"
    local color="${PROMPT_PALETTE[git.commited]}"
    if [[ ${git_status} =~ "Changes to be committed:" ]]; then
      color="${PROMPT_PALETTE[git.staged]}"
    elif [[ ${git_status} =~ "Changes not staged for commit:" ]]; then
      color="${PROMPT_PALETTE[git.modified]}"
    elif [[ ${git_status} =~ "Untracked files:" ]]; then
      color="${PROMPT_PALETTE[git.untracked]}"
    else
      color="${PROMPT_PALETTE[git.other]}"
    fi
    prompts[git]=" ${PROMPT_PALETTE[conj]}on ${PROMPT_PALETTE[normal]}(${color}${git_branch}${PROMPT_PALETTE[normal]})"
    prompts_len[git]=$(( ${#git_branch} + 6 ))
  else
    prompts[git]=""
    prompts_len[git]=0
  fi
}


set_venv_info() {
  if [[ -n ${VIRTUAL_ENV} ]]; then
    prompts[venv]="${PROMPT_PALETTE[normal]}(${PROMPT_PALETTE[venv]}venv${PROMPT_PALETTE[normal]})"
    prompts_len[venv]=5
  else
    prompts[venv]=""
    prompts_len[venv]=0
  fi
}


set_last_status() {
  local last_code=$?
  if (( ${last_code} == 0 )); then
    prompts[exit]="${PROMPT_SYMBOL[exit.success]}"
    prompts_len[exit]=${#PROMPT_SYMBOL[exit.success]}
  else
    prompts[exit]="${PROMPT_PALETTE[exit.mark]}exit:${PROMPT_PALETTE[exit]}${last_code}"
    prompts_len[exit]=$(( ${#last_code} + 5 ))
  fi
}


set_typing_pointer() {
  prompts[typing]="${PROMPT_SYMBOL[arrow]}${PROMPT_PALETTE[reset]}"
}


main_prompt() {
  local width=$(tput cols)
  local corner_top="${prompts[margin]}${PROMPT_PALETTE[normal]}${PROMPT_SYMBOL[corner.top]}"
  local corner_bottom="${PROMPT_PALETTE[reset]}${PROMPT_PALETTE[normal]}${PROMPT_SYMBOL[corner.bottom]}"
  local left_part="${corner_top}${prompts[host]}${prompts[user]}${prompts[path]}${prompts[git]}"
  local right_part="${prompts[time]}${prompts[elapsed]}"
  local prompt_len=$(( prompts_len[host] + prompts_len[user] + prompts_len[path] + prompts_len[git] + prompts_len[time] + prompts_len[elapsed] ))
  local padding="$(( width - prompt_len - 3))"
  if (( padding > 0 )); then
    echo "${left_part}${(r:${padding}:)""}${right_part}"
  else
    echo "${left_part}"
  fi
  echo "${corner_bottom}${prompts[venv]}${prompts[typing]} "
}


sub_prompt() {
  echo "${prompts[exit]}"
}


preexec() {
  set_exec_timestamp
}


precmd() {
  set_last_status  # must be loaded at first!
  set_margin
  set_hostname
  set_user
  set_current_path
  set_current_time
  set_elapsed_time
  set_git_info
  set_venv_info
  set_typing_pointer
}


PROMPT='$(main_prompt)'
RPROMPT='$(sub_prompt)'





REPORTTIME=30
TIMEFMT='JOB:  %J
TIME: %E (user: %U, kernel: %S)
CPU:  %P'



source ~/30_grc.zsh
