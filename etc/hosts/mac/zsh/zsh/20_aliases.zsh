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


::() {
  local session="$1"
  if [[ -z ${session} ]]; then
    tmux
  elif [[ -n $(tmux ls -F "#{session_name}" | grep -x "${session}") ]]; then
    tmux attach -t "${session}"
  else
    tmux $@
  fi
}


colortest() {
  for c in {000..255}; do
    echo -n "\e[38;5;${c}m $c"
    (( $(($c%16)) == 15 )) && echo
  done
}


alias -s py=python
alias -s jl=julia
alias -s {gz,tgz,zip,lzh,bz2,tbz,Z,tar,arj,xz}=xx
alias -s {png,jpg,bmp,PNG,JPG,BMP}=preview

#alias -g C='| pbcopy'
#alias -g H='| head'
#alias -g T='| tail'
#alias -g X='| xargs'

alias :q='exit'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ..2='cd ../..'
alias ..3='cd ../../..'
alias ..4='cd ../../../..'
alias ..5='cd ../../../../..'

alias b='brew'
alias c='pbcopy'
alias g='git'
alias m='move'
alias o='open'
alias p='ping'
alias r='rm -i'
alias s='sudo'
alias x='chmod +x'
alias y='yes'

alias an='ansible'
alias be='bundle exec'
alias bi='bundle install'
alias bu='bundle update'
alias dc='docker-compose'
alias dk='docker'
alias ga='git add'
alias gb='git branch'
alias gc='git commit'
alias gd='git diff'
alias gf='git fetch'
alias gp='git push'
alias gs='git status'
alias kc='kubectl'
alias pp='ping6'
alias rc='bundle exec rails c'

alias dot='cd $HOME/dotfiles'
alias gco='git checkout'
alias ghc='git clone git@github.com:'
alias gpp='git pull'
alias ipy='ipython3'
alias mkd='mkdir -p'
alias ssa='ssh-agent zsh'
alias :::='tmuxinator'

alias free='free -h'
alias grep='grep -n --color=auto'
alias http='python3 -m http.server'
alias less='less --no-init --quit-if-one-screen'
alias myip='curl -s ipinfo.io | jq'
alias egrep='egrep -n --color=auto'
alias fgrep='fgrep -n --color=auto'
alias preview='open -a Preview'


if (( $+commands[arch] )); then
  alias x64='exec arch -arch x86_64 "$SHELL"'
  alias a64='exec arch -arch arm64e "$SHELL"'
fi


if whence -p trash 1> /dev/null; then
  alias rm='trash'
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
  export EDITOR=vim
  alias vi='vim'
fi


if whence -p nvim 1> /dev/null; then
  export EDITOR=nvim
  alias vi='nvim'
  alias vim='nvim'
  alias emacs='nvim'
  alias nano='nvim'
  alias pico='nvim'
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
