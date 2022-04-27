setopt ALWAYS_TO_END
setopt ALWAYS_LAST_PROMPT
setopt AUTOPUSHD
setopt AUTO_CD
setopt AUTO_LIST
setopt AUTO_MENU
setopt AUTO_PARAM_SLASH
setopt AUTO_PARAM_KEYS
setopt BANG_HIST
setopt CORRECT
setopt COMPLETE_IN_WORD
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

export HISTSIZE=1000000
export SAVEHIST=1000000
export HISTFILE=$HOME/.zhistory
export PATH_BOOKMARK=$HOME/.zsh_pathbook

[[ -f ${PATH_BOOKMARK} ]] || touch ${PATH_BOOKMARK}

#export TERM=screen-256color
export TERM=xterm-256color
export LANG=en_US.UTF-8
export LANGUAGE=$LANG
export LC_CTYPE=$LANG
export LC_ALL=$LANG

## see: https://github.com/ogham/exa/issues/544
export LS_COLORS="di=1;34:ln=0;36:pi=0;33:bd=1;33:cd=1;33:so=1;31:ex=1;32:*README=1;4;33:*README.txt=1;4;33:*README.md=1;4;33:*readme.txt=1;4;33:*readme.md=1;4;33:*.ninja=1;4;33:*Makefile=1;4;33:*Cargo.toml=1;4;33:*SConstruct=1;4;33:*CMakeLists.txt=1;4;33:*build.gradle=1;4;33:*pom.xml=1;4;33:*Rakefile=1;4;33:*package.json=1;4;33:*Gruntfile.js=1;4;33:*Gruntfile.coffee=1;4;33:*BUILD=1;4;33:*BUILD.bazel=1;4;33:*WORKSPACE=1;4;33:*build.xml=1;4;33:*Podfile=1;4;33:*webpack.config.js=1;4;33:*meson.build=1;4;33:*composer.json=1;4;33:*RoboFile.php=1;4;33:*PKGBUILD=1;4;33:*Justfile=1;4;33:*Procfile=1;4;33:*Dockerfile=1;4;33:*Containerfile=1;4;33:*Vagrantfile=1;4;33:*Brewfile=1;4;33:*Gemfile=1;4;33:*Pipfile=1;4;33:*build.sbt=1;4;33:*mix.exs=1;4;33:*bsconfig.json=1;4;33:*tsconfig.json=1;4;33:*.zip=0;31:*.tar=0;31:*.Z=0;31:*.z=0;31:*.gz=0;31:*.bz2=0;31:*.a=0;31:*.ar=0;31:*.7z=0;31:*.iso=0;31:*.dmg=0;31:*.tc=0;31:*.rar=0;31:*.par=0;31:*.tgz=0;31:*.xz=0;31:*.txz=0;31:*.lz=0;31:*.tlz=0;31:*.lzma=0;31:*.deb=0;31:*.rpm=0;31:*.zst=0;31:*.lz4=0;31"

export HGENCODING='utf-8'
export GPG_TTY=$TTY
export WORDCHARS='*?.-[]~=&;!#$%^(){}<>'
export PAGER=less
export LESS='-g -i -M -R -S -W -z-4 -x4'
export EDITOR="vim"
bindkey -e  # set explicitly, or zsh use vi-mode binding by default
bindkey '^O' autosuggest-accept

zstyle ':completion:*'                 completer _expand _complete _match _prefix _approximate _list _history
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
zstyle ':completion:*:descriptions'    format '%F{YELLOW}completing %B%d%b'$DEFAULT
zstyle ':completion:*:descriptions'    format '%F{yellow}Completing %B%d%b%f'$DEFAULT
zstyle ':completion:*:manuals'         separate-sections true
zstyle ':completion:*:messages'        format '%F{YELLOW}%d'$DEFAULT
zstyle ':completion:*:options'         description 'yes'
zstyle ':completion:*:sudo:*'          command-path $path
zstyle ':completion:*:warnings'        format '%F{RED}No matches for:''%F{YELLOW} %d'$DEFAULT

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
  ssh-add $HOME/.ssh/MASTER_KEY/mi2428.master.id_ed25519
  ssh-add $HOME/.ssh/GIT/mi2428.git.id_ed25519
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

zle -N severity_clear _severity_clear
zle -N severity_level1 _severity_level1
zle -N severity_level2 _severity_level2
zle -N severity_level3 _severity_level3
zle -N severity_level4 _severity_level4
zle -N toggle_ssh_prompt _toggle_ssh_prompt
zle -N toggle_path_bookmark _toggle_path_bookmark

bindkey '^[0' severity_clear
bindkey '^[1' severity_level1
bindkey '^[2' severity_level2
bindkey '^[3' severity_level3
bindkey '^[4' severity_level4
bindkey '^[s' toggle_ssh_prompt
bindkey '^[b' toggle_path_bookmark

autoload -Uz colors && colors
autoload -Uz compinit && compinit  # all completion settings must be done before
