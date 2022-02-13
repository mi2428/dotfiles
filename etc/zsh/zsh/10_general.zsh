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

export TERM=screen-256color
export LANG=en_US.UTF-8
export LANGUAGE=$LANG
export LC_CTYPE=$LANG
export LC_ALL=$LANG
export LC_TERMINAL=iTerm2

export HGENCODING='utf-8'
export GPG_TTY=$TTY
export WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'
export PAGER=less
export LESS='-g -i -M -R -S -W -z-4 -x4'
export EDITOR="vim"
bindkey -e  # set explicitly, or zsh use vi-mode binding by default
bindkey '^O' autosuggest-accept

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

autoload -Uz colors && colors
autoload -Uz compinit && compinit

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

if [[ -n ${SSH_AGENT_PID} ]] && ! ssh-add -l 1> /dev/null; then
  ssh-add $HOME/.ssh/MASTER_KEY/mi2428.master.id_ed25519
  echo
fi

REPORTTIME=300
TIMEFMT='JOB:  %J
TIME: %E (user: %U, kernel: %S)
CPU:  %P'


_severity_clear() {
  export PROMPT_SEVERITY=0
}

_severity_level1() {
  export PROMPT_SEVERITY=1
}

_severity_level2() {
  export PROMPT_SEVERITY=2
}

_severity_level3() {
  export PROMPT_SEVERITY=3
}

_severity_level4() {
  export PROMPT_SEVERITY=4
}

zle -N severity_clear _severity_clear
zle -N severity_level1 _severity_level1
zle -N severity_level2 _severity_level2
zle -N severity_level3 _severity_level3
zle -N severity_level4 _severity_level4

bindkey '^[0' severity_clear
bindkey '^[1' severity_level1
bindkey '^[2' severity_level2
bindkey '^[3' severity_level3
bindkey '^[4' severity_level4
