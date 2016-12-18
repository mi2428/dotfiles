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

function man() {
    LESS_TERMCAP_mb=$'\e[01;31m'       \
    LESS_TERMCAP_md=$'\e[01;38;5;74m'  \
    LESS_TERMCAP_me=$'\e[0m'           \
    LESS_TERMCAP_se=$'\e[0m'           \
    LESS_TERMCAP_so=$'\e[38;5;246m'    \
    LESS_TERMCAP_ue=$'\e[0m'           \
    LESS_TERMCAP_us=$'\e[04;38;5;146m' \
    /usr/bin/man "$@"
}

export CLICOLOR=true
export LSCOLORS=Exfxcxdxbxegedabagacad  
export LS_COLORS='di=01;34:ln=01;35:so=01;32:ex=01;31:bd=40;33:cd=40;33:su=41;30:sg=46;30:tw=42;30:ow=43;30'
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
autoload -U colors; colors
