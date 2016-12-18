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


##
# ショートカット
##
alias :q="exit"
alias py="python"
alias py3="python3"
alias ipy="ipython2"
alias sss="source ~/.zshrc"
alias lg="cd /var/log"
alias l="ls"
alias ll="ls -l"
alias la="ls -alr"
alias df="df -h"
alias cl="clear"
alias x="startx"
alias ::="tmux"
alias gosh="rlwrap -p gosh"
alias p8="ping 8.8.8.8"
alias s="source"
alias ls="ls -G"
alias p="sudo purge"


##
# lsしたらcdする
##
function cd() {
	builtin cd $1 && ls
}
