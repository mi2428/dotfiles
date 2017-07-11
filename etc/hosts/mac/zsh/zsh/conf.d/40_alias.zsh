##
# デフォルトで色を付ける
##
alias grep="grep -n --color=auto"

function man() {
    env \
    LESS_TERMCAP_mb=$(printf "\e[1;31m") \
    LESS_TERMCAP_md=$(printf "\e[1;31m") \
    LESS_TERMCAP_me=$(printf "\e[0m") \
    LESS_TERMCAP_se=$(printf "\e[0m") \
    LESS_TERMCAP_so=$(printf "\e[1;44;33m") \
    LESS_TERMCAP_ue=$(printf "\e[0m") \
    LESS_TERMCAP_us=$(printf "\e[1;32m") \
    man "$@"
}

function cd() {
    builtin cd $1 && ls
}

function mcd() {
    mkdir -p $1 && cd $1
}

function open() {
    spacefm $1 2> /dev/null 1> /dev/null &
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
alias py="python"
alias py3="python3"
alias ipy="ipython"
alias sss="source ~/.zshrc"
alias lg="cd /var/log"
alias l="ls"
alias ll="ls -l"
alias la="ls -alr"
alias df="df -h"
alias cl="clear"
alias x="startx"
alias zz="mlterm -L true > /dev/null 2>&1 &"
alias gosh="rlwrap -p gosh"
alias p8="ping 8.8.8.8"
alias sshv="ssh -v"
alias pd="popd"
alias ff="fzf"

alias vi="vim"
if whence -p nvim 1> /dev/null; then
    alias vim="nvim"
    alias vi="nvim"
fi
alias ls="ls -G"

alias gcc32="gcc -m32 -O0 -fno-asynchronous-unwind-tables"

