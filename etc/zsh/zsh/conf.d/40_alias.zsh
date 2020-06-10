function cd() {
    builtin cd $1 && ls
}

function mcd() {
    mkdir -p $1 && cd $1
}

function psgrep() {
    ps aux | head -n 1
    ps aux | grep $@
}

function open() {
    nautilus $1 2> /dev/null 1> /dev/null &
}

function fe() {
    local file
    file="$(fzf --query="$1" --select-1 --exit-0)"
    [ -n "$file" ] && ${EDITOR:-vim} "$file"
}

function fd() {
    local dir
    dir=$(find ${1:-*} -path '*/\.*' -prune -o -type d -print 2> /dev/null | fzf +m) && \
    cd "$dir"
}

function fkill() {
    ps -ef | sed 1d | fzf -m | awk '{print $2}' | xargs kill -${1:-9}
}

function fh() {
    eval $(([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s | sed 's/ *[0-9]* *//')
}

alias :q="exit"
alias ZQ="exit"
alias py="python3"
alias ipy="ipython"
alias sss="exec zsh"
alias lg="cd /var/log"

alias l="ls"
alias ll="ls -l"
alias la="ls -alr"
if whence -p exa 1> /dev/null; then
    alias l="exa"
    alias ll="exa -l"
    alias la="exa -l  -arbghi --git"
    alias lr="exa -lR -arbghi  --git -I .git"
    alias lt="exa -lT -arbghi  --git -I .git"
    alias laa="exa -l -arbghi@ --git"
fi

alias df="df -h"
alias cl="clear"
alias x="startx"
alias zz="mlterm -L true > /dev/null 2>&1 &"
alias gosh="rlwrap -p gosh"
alias ping8="ping 8.8.8.8"
alias pingg="ping www.google.com"
alias sshv="ssh -v"
alias pd="popd"
alias ff="fzf"
alias ptr="paris-traceroute"
alias grep="grep -n --color=auto"
alias dk="docker"
alias dc="docker-compose"
alias kc="kubectl"

whence colordiff 1> /dev/null 2>&1 && alias diff='colordiff'

alias vi="vim"
if whence -p nvim 1> /dev/null; then
    alias vim="nvim"
    alias vi="nvim"
fi
alias ls="ls --color=auto"

alias gcc32="gcc -m32 -O0 -fno-asynchronous-unwind-tables"
