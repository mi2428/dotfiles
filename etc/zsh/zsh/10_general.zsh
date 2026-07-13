setopt ALWAYS_LAST_PROMPT
setopt ALWAYS_TO_END
setopt AUTOPUSHD
setopt AUTO_CD
setopt AUTO_LIST
setopt AUTO_MENU
setopt AUTO_PARAM_KEYS
setopt AUTO_PARAM_SLASH
setopt BANG_HIST
setopt COMPLETE_IN_WORD
setopt CORRECT
setopt EXTENDED_GLOB
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt IGNORE_EOF
setopt LIST_PACKED
setopt LIST_TYPES
setopt MAGIC_EQUAL_SUBST
setopt NONOMATCH
setopt NOTIFY
setopt NO_AUTOREMOVESLASH
setopt NO_BEEP
setopt NO_LIST_BEEP
setopt PROMPT_SUBST
setopt PUSHD_IGNORE_DUPS
setopt SHARE_HISTORY
setopt TRANSIENT_RPROMPT

export HISTSIZE=1000000
export SAVEHIST=1000000
export HISTFILE=$HOME/.zhistory
export PATH_BOOKMARK=$HOME/.zsh_pathbook

export NOTES_DIR=$HOME/notes
export NOTES_DIRECTORY=$HOME/notes

[[ -f ${PATH_BOOKMARK} ]] || touch ${PATH_BOOKMARK}

#export TERM=screen-256color
export TERM=xterm-256color
export LANG=en_US.UTF-8
export LANGUAGE=$LANG
export LC_CTYPE=$LANG
export LC_ALL=$LANG
export VIRTUAL_ENV_DISABLE_PROMPT=1

export HGENCODING='utf-8'
export GPG_TTY=$TTY
export WORDCHARS='*?.-[]~=&;!#$%^(){}<>'
export PAGER=less
export LESS='-g -i -M -R -S -W -z-4 -x4'
export EDITOR="vim"
bindkey -e  # set explicitly, or zsh use vi-mode binding by default
(( ${+widgets[autosuggest-accept]} )) && bindkey '^O' autosuggest-accept


zstyle ':completion:*'                 completer _expand _expand_alias _complete _match _prefix _approximate _list _history
zstyle ':completion:*'                 group-name ''
zstyle ':completion:*'                 list-colors '${(s.:.)LS_COLORS}'
zstyle ':completion:*'                 list-separator '-->'
zstyle ':completion:*'                 matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*'                 use-cache true
zstyle ':completion:*'                 verbose yes
zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters
zstyle ':completion:*:*files'          ignored-patterns '*?.o' '*?~' '*\#'
zstyle ':completion:*:cd:*'            ignore-parents parent pwd
zstyle ':completion:*:cd:*'            tag-order local-directories path-directories
zstyle ':completion:*:commands'        rehash 1
zstyle ':completion:*:default'         menu select=2
zstyle ':completion:*:descriptions'    format "%F{$CTP_YELLOW}Completing %B%d%b%f"$DEFAULT
zstyle ':completion:*:manuals'         separate-sections true
zstyle ':completion:*:messages'        format "%F{$CTP_YELLOW}%d%f"$DEFAULT
zstyle ':completion:*:options'         description 'yes'
zstyle ':completion:*:sudo:*'          command-path $path
zstyle ':completion:*:warnings'        format "%F{$CTP_RED}No matches for:%f%F{$CTP_YELLOW} %d%f"$DEFAULT

if [[ -d ~/.ssh ]]; then
  local h=()
  if [[ -r ~/.ssh/known_hosts ]]; then
    h=($h $(awk '{print $1}' $HOME/.ssh/known_hosts | cut -d ',' -f 1 | grep -v '\[' | sort | uniq))
  fi
  if [[ -r ~/.ssh/config ]]; then
    h=($h $(egrep 'Host\s+[^\*]+[^\*]$' $HOME/.ssh/config  | awk '{print $NF}'))
  fi
  if [[ $#h -gt 0 ]]; then
    zstyle ':completion:*:ssh:*' hosts $h
    zstyle ':completion:*:scp:*' hosts $h
    zstyle ':completion:*:rsync:*' hosts $h
    zstyle ':completion:*:slogin:*' hosts $h
  fi
fi

if [[ -n ${SSH_AGENT_PID} ]] && ! ssh-add -l 1> /dev/null; then
  ssh-add $HOME/.ssh/masterkey/mi2428.master.id_ed25519
  ssh-add $HOME/.ssh/masterkey.old/mi2428.master.id_ed25519
  ssh-add $HOME/.ssh/masterkey.old/mi2428.master.id_rsa
  ssh-add $HOME/.ssh/git/mi2428.git.id_ed25519
  ssh-add $HOME/.ssh/soracom.io/kagari-teo.pem

  if [[ -d $HOME/.ssh/soracom.io ]]; then
    ssh-add $HOME/.ssh/soracom.io/sorao.id_rsa
  fi
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

_toggle_ssh_prompt() {
  [[ -z HIDE_SSH_PROMPT ]] && export HIDE_SSH_PROMPT=1
  HIDE_SSH_PROMPT=$(( (HIDE_SSH_PROMPT + 1) % 2 ))
}

_toggle_path_bookmark() {
  if \grep -q "^${PWD}$" ${PATH_BOOKMARK}; then
    sed -i "" -e "/^${PWD//\//\\/}$/d" ${PATH_BOOKMARK}
  else
    echo "${PWD}" >> ${PATH_BOOKMARK}
  fi
}

_sanitize_history() {
  if whence -p ggrep >/dev/null; then
    ggrep -P '^[[:ascii:]]+$' $HOME/.zhistory > $HOME/._zhistory
    mv $HOME/._zhistory $HOME/.zhistory
  fi
}


zle -N severity_clear       _severity_clear
zle -N severity_level1      _severity_level1
zle -N severity_level2      _severity_level2
zle -N severity_level3      _severity_level3
zle -N severity_level4      _severity_level4
zle -N toggle_ssh_prompt    _toggle_ssh_prompt
zle -N toggle_path_bookmark _toggle_path_bookmark
zle -N sanitize_history     _sanitize_history

bindkey '^[0' severity_clear
bindkey '^[1' severity_level1
bindkey '^[2' severity_level2
bindkey '^[3' severity_level3
bindkey '^[4' severity_level4
bindkey '^[s' toggle_ssh_prompt
bindkey '^[b' toggle_path_bookmark
bindkey '^[h' sanitize_history


autoload -Uz colors && colors
autoload -Uz compinit && compinit  # all completion settings must be done before

# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#enable-shell-autocompletion
if (( ${+commands[kubectl]} )); then
  source <(kubectl completion zsh)
fi

# https://raw.githubusercontent.com/tmuxinator/tmuxinator/master/completion/tmuxinator.zsh
if (( ${+commands[tmuxinator]} )); then
  _tmuxinator() {
    local commands projects
    commands=(${(f)"$(tmuxinator commands zsh)"})
    projects=(${(f)"$(tmuxinator completions start)"})

    if (( CURRENT == 2 )); then
      _alternative \
        'commands:: _describe -t commands "tmuxinator subcommands" commands' \
        'projects:: _describe -t projects "tmuxinator projects" projects'
    elif (( CURRENT == 3)); then
      case $words[2] in
        copy|cp|c|debug|delete|rm|open|o|start|s|edit|e)
          _arguments '*:projects:($projects)'
        ;;
      esac
    fi

    return
  }

  compdef _tmuxinator tmuxinator
fi
