for X in {16..255}; do
    COLFG256[${X}]=$(echo "\e[38;5;${X}m")
    COLBG256[${X}]=$(echo "\e[48;5;${X}m")
done
unset X
COL_DEF="$(echo '\e[0m')"
COL_BOLD="$(echo '\e[1m')"

function colortest {
    for c in {000..255}; do
        echo -n "\e[38;5;${c}m $c"
        [ $(($c%16)) -eq 15 ] && echo
    done
    echo
}


## solarized-dark
man() {
    env \
        LESS_TERMCAP_mb=$(printf "\e[1;31m") \
        LESS_TERMCAP_md=$(printf "\e[1;31m") \
        LESS_TERMCAP_me=$(printf "\e[0m") \
        LESS_TERMCAP_se=$(printf "\e[0m") \
        LESS_TERMCAP_so=$(printf "\e[0;37;102m") \
        LESS_TERMCAP_ue=$(printf "\e[0m") \
        LESS_TERMCAP_us=$(printf "\e[4;32m") \
        PAGER=/usr/bin/less \
        _NROFF_U=1 \
        PATH=${HOME}/bin:${PATH} \
    man "$@"
}

export CLICOLOR=true
export LSCOLORS=Exfxcxdxbxegedabagacad  
export LS_COLORS='di=01;34:ln=01;35:so=01;32:ex=01;31:bd=40;33:cd=40;33:su=41;30:sg=46;30:tw=42;30:ow=43;30'
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
autoload -U colors; colors
