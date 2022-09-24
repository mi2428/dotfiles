cd() {
  if whence -p exa 1> /dev/null; then
    builtin cd $1 && EXA_ICON_SPACING=1 exa --icons .
  else
    builtin cd $1 && ls --color=auto .
  fi
}


mcd() {
  #mkdir -p $1 && pushd $1
  mkdir -p $1 && cd $1
}


pd() {
  if (( $# == 1 )); then
    pushd "$1"
  else
    popd
  fi

  if whence -p exa 1> /dev/null; then
    EXA_ICON_SPACING=1 exa --icons .
  else
    ls --color=auto .
  fi
}


goto() {
  local keyword="${1:-/}"
  local matched="$(\egrep "$keyword" $PATH_BOOKMARK)"
  local n_matched=$(wc -l <<< "$matched")
  local dst="${matched:-''}"
  if [[ -z "$matched" ]] || (( $n_matched > 1 )); then
    dst="$(fzf -e --tac --no-sort <<< $matched --preview 'tree -L 3 -C {} | head -200')"
  fi
  /usr/bin/sed -i "" -e "/^${dst//\//\\/}$/d" ${PATH_BOOKMARK} && echo "${dst}" >> ${PATH_BOOKMARK}
  builtin cd "${dst}"
}


get() {
  mv -i $@ .
}


showopt() {
  set -o | sed -e 's/^no\(.*\)on$/\1  off/' -e 's/^no\(.*\)off$/\1  on/' | \grep --color=auto -E '.*on$|$'
}


p() {
  if (( $# == 0 )); then
    ping 8.8.8.8
  else
    ping $@
  fi
}


pp() {
  if (( $# == 0 )); then
    ping6 2001:4860:4860::8888
  else
    ping6 $@
  fi
}


ppp() {
  if (( $# == 0 )); then
    ping -c 4 -i 0.25 8.8.8.8
    echo
    ping6 -c 4 -i 0.25 2001:4860:4860::8888
  else
    ping $@
    echo
    ping6 $@
  fi
}


m() {
  if (( $# == 0 )); then
    mtr -4 -b -i 0.1 8.8.8.8
  else
    mtr -4 -b -i 0.1 $@
  fi
}


mm() {
  if (( $# == 0 )); then
    mtr -6 -b -i 0.1 2001:4860:4860::8888
  else
    mtr -6 -b -i 0.1 $@
  fi
}


mmm() {
  local opt=""
  local target=$1

  case $opt in
    -h)
      tmux split-window -h -p 66 "sudo grc --colour=auto mtr -4 -b -i 0.1 $target"
      tmux split-window -h "sudo grc --colour=auto mtr -6 -b -i 0.1 $target"
      ;;
    -v|*)
      tmux split-window -v -p 66 "sudo grc --colour=auto mtr -4 -b -i 0.1 $target"
      tmux split-window -v "sudo grc --colour=auto mtr -6 -b -i 0.1 $target"
      ;;
  esac
}


dk() {
  case $1 in
    art|rt)
      docker start ${@:2}
      return 0
      ;;

    op)
      docker stop ${@:2}
      return 0
      ;;

    im)
      docker images ${@:2}
      return 0
      ;;

    bd)
      docker build ${@:2}
      return 0
      ;;

    ex)
      docker exec ${@:2}
      return 0
      ;;

    kl)
      docker kill ${@:2}
      return 0
      ;;

    lg)
      docker logs ${@:2}
      return 0
      ;;

    pl)
      if (( $# == 1 )); then
        for image in $(docker images --format '{{.Repository}}:{{.Tag}}' --filter "dangling=false" | grep -v '<none>' | fzf --multi); do
          docker pull ${image}
        done
      elif [[ $2 == "ubuntu" ]]; then
        docker pull ghcr.io/mi2428/ubuntu:latest
      else
        docker pull ${@:2}
      fi
      return 0
      ;;

    cc)
      docker commit ${@:2}
      return 0
      ;;

    vl)
      docker volume ${@:2}
      return 0
      ;;

    rmi)
      if (( $# == 1 )); then
        docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' --filter "dangling=false" | grep -v '<none>' | fzf --multi)
        return 0
      else
        docker rmi ${@:2}
      fi
      ;;

    *)
      docker $@
      ;;
  esac
}


dcx() {
  local name="$1"
  local args="${@:2}"
  [[ -z $args ]] && args="/bin/bash"
  docker-compose exec ${name} ${args}
}


dot() {
  if (( $# == 0 )); then
    cd $HOME/dotfiles
    return 0
  fi

  ## execute in subshell so as not to move current directory
  case $1 in
    cc|commit)
      local message="${@:2}"
      (builtin cd $HOME/dotfiles 2>/dev/null; git add . 1>/dev/null 2>&1; git commit -m "$message")
      return 0
      ;;

    k|keep)
      (builtin cd $HOME/dotfiles 2>/dev/null; git add . 1>/dev/null 2>&1; git commit -m "keep: $(date)")
      return 0
      ;;

    d|diff)
      (builtin cd $HOME/dotfiles 2>/dev/null; git diff-index --quiet HEAD || git diff)
      return 0
      ;;

    lg|log)
      (builtin cd $HOME/dotfiles 2>/dev/null; tig)
      return 0
      ;;

    pl|pull)
      (builtin cd $HOME/dotfiles 2>/dev/null; git pull)
      return 0
      ;;

    ps|push)
      (builtin cd $HOME/dotfiles 2>/dev/null; git push)
      return 0
      ;;

    s|sync)
      (builtin cd $HOME/dotfiles 2>/dev/null; git pull && git push)
      return 0
      ;;

    rollback)
      (builtin cd $HOME/dotfiles 2>/dev/null; git checkout .)
      return 0
      ;;

    actions)
      if whence -p open 2>/dev/null 1>&2; then
        open https://github.com/mi2428/dotfiles/actions https://github.com/mi2428/ubuntu/actions
      else
        echo "open your browser and visit:"
        echo " - https://github.com/mi2428/dotfiles/actions"
        echo " - https://github.com/mi2428/ubuntu/actions"
      fi
      return 0
      ;;

    -h|--help|*)
      echo "usage: dot [options...]"
      echo " (empty)               move to $HOME/dotfiles"
      echo " cc, commit [message]  alias of \`git add . && git commit -m\` command"
      echo " d,  diff              alias of \`git diff\` command"
      echo " lg, log               alias of \`tig\` command"
      echo " pl, pull              alias of \`git pull\` command"
      echo " ps, push              alias of \`git push\` command"
      echo " s,  sync              run pull and then push"
      echo "     rollback          alias of \`git checkout .\` command"
      echo "     actions           open GitHub Actions"
      echo " h,  help              this help text"
      return 0
      ;;
  esac
}

addr() {
  local addrtxt="$HOME/io/addr/addr.txt"
  local keyword="$1"

  if [[ ! -f ${addrtxt} ]]; then
    echo "missing: ${addrtxt}"
    return 1
  fi

  pushd $(dirname ${addrtxt}) 1>/dev/null 2>&1
  #git pull 2>/dev/null 1>&2

  if [[ -z ${keyword} ]]; then
    bat ${addrtxt}
  elif [[ ${keyword} == "--edit" ]]; then
    git pull 2>/dev/null || true
    vim ${addrtxt}
    git add ${addrtxt} 2>/dev/null && git commit -m "keep: $(date)" 2>/dev/null && git push 2>/dev/null || true
  else
    local data=$(cat ${addrtxt} | \grep -v '^#' | \grep -v '^$' | \grep -i "${keyword}")
    if [[ -n ${data} ]]; then
      echo "IP address              Hostname                    Notes"
      echo ${data}
    else
      echo "nothing matched: ${keyword}"
    fi
  fi
}


##
## DEPRECATED:
## Use pimeterry/notes instead (https://github.com/pimterry/notes)
##
# note() {
#   local title="$@"
#   local ts="$(date +%Y.%m.%d-%H:%M:%S)"
# 
#   mkdir -p $NOTEDIR
#   title="${title// /-}"
# 
#   if [[ -n $title ]]; then
#     local filename="${NOTEDIR}/${title}__${ts}.md"
#     $(which $EDITOR) $filename
#   else
#     $(which $EDITOR) -p $(\ls -1rt `find $NOTEDIR -type f -follow` | fzf --multi --preview 'bat --color=always {}')
#   fi
# }


what() {
  local filepath="$1"

  case $(file -b $filepath) in
    'PEM certificate')
      openssl x509 -in $filepath -noout -text
      ;;
  esac
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


ipapi() {
  if [[ -n $1 ]]; then
    curl -s http://ip-api.com/json/${1} | jq .
  else
    curl -s http://ip-api.com/json | jq .
  fi
}


ghc() {
  local repo="$1"
  if (( $# == 2 )); then
    repo="${1}/${2}"
  fi
  git clone --recursive git@github.com:${repo}
}


sshsocks() {
  local host="$1"
  local port="$2"
  ssh -C -D ${port} -f -N ${host}
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


dotenv() {
  local _path="$1"

  if [[ ! -f "$_path" ]] && [[ -f .env ]]; then
    _path=".env"
  fi

  export $(\grep -v '^#' "$_path" | xargs)
}

## load .env



::() {
  local session="$1"
  if [[ -z ${session} ]]; then
    tmux
  elif [[ -n $(tmux ls -F "#{session_name}" | \grep -x "${session}") ]]; then
    tmux attach -t "${session}"
  else
    tmux $@
  fi
}


gk() {
  local target="$@"
  if [[ -z $target ]]; then
    target=$(dirname `git rev-parse --git-dir`)
  fi

  git add ${target}
  git commit -m "keep: $(date)"

  if [[ -n $(git remote -v) ]]; then
    git push || git pull && git push
  fi
}


gadd() {
  local selected
  selected=$(unbuffer git status -s | fzf -m --ansi --preview="echo {} | awk '{print \$2}' | xargs git diff --color" | awk '{print $2}')
  if [[ -n "${selected}" ]]; then
    selected=$(tr '\n' ' ' <<< "${selected}")
    git add ${selected}
    echo "Completed: git add ${selected}"
  fi
}


fe() {
  local files
  IFS=$'\n' files=($(fzf-tmux --query="$1" --multi --select-1 --exit-0))
  [[ -n "$files" ]] && ${EDITOR:-vim} "${files[@]}"
}


fkill() {
  local pid
  pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
  if [ "x$pid" != "x" ]; then
    echo $pid | xargs kill -${1:-9}
  fi
}


dor() {
  docker run -it $@ `docker images --format "{{.Repository}}:{{.Tag}}" --filter "dangling=false" | fzf`
}


ffind() {
  for key in ${@}; do
    find . $opt -name "*${key}*" | \grep --color='auto' "${key}"
  done
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

alias b='bat'
alias c='pbcopy'
alias g='git'
alias j='jmp'
alias n='notes'
alias o='open'
alias r='rm -i'
alias s='sudo'
alias x='chmod +x'
alias y='yes'
alias z='exec env PROMPT_SEVERITY=${PROMPT_SEVERITY} OUTSIDE_HOSTNAME=${OUTSIDE_HOSTNAME} zsh --login'

alias an='ansible'
alias be='bundle exec'
alias bi='bundle install'
alias bu='bundle update'
alias dc='docker-compose'
alias ga='git add'
alias gb='git branch'
alias gc='git commit -s -m'
alias gd='git diff'
alias gf='git fetch'
alias gp='git push'
alias gs='git status'
alias kc='kubectl'
alias py='python3'
alias rc='bundle exec rails c'

alias :::='tmuxinator'
alias io='cd $HOME/io'
alias dcl='docker-compose logs -f'
alias dow='cd $HOME/Downloads'
alias dox='docker exec -it `docker ps --format "{{.Names}}" | fzf`'
alias gco='git checkout'
alias gpl='git pull'
alias ipf='iperf3'
alias ipp='ip -6'
alias ipy='ipython3'
alias jmp='goto'
alias mkd='mkdir -p'
alias ssa='ssh-agent zsh'

alias dorm='docker rm `docker ps -qa` 2>/dev/null'
alias dormi='docker rmi `docker images --filter "dangling=true" -q` 2>/dev/null'
alias editssh='vim $HOME/.ssh/config'
alias egrep='egrep -n --color=auto'
alias fgrep='fgrep -n --color=auto'
alias free='free -h'
alias grep='grep -n --color=auto'
alias httpserver='python3 -m http.server'
alias less='less --no-init --quit-if-one-screen'
alias myip='curl -s https://ipinfo.io | jq'
alias sshh='sshuttle'


#if whence -p ag 1> /dev/null; then
#  alias grep="ag"
#fi


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
  alias mg='nvim'
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


if whence -p rbenv 1>/dev/null; then
  eval "$(rbenv init - zsh)"
fi
