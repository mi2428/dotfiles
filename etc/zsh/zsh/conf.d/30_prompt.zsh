if [[ -n "$(echo $TTY | \grep pts)" ]]; then
    local blue1=${COLFG256[069]}
    local blue2=${COLFG256[075]}
    local blue3=${COLFG256[045]}
    local green1=${COLFG256[034]}
    local green2=${COLFG256[036]}

    function current_git_status() {
        local name st color action
        [[ "$PWD" =~ '/\.git(/.*)?$' ]] && return
        name=$(git symbolic-ref --short HEAD 2> /dev/null)
        [[ -z "$name" ]] && return
        st=$(git status 2> /dev/null)
        color="%F{red}%B"
        [[ -n $(echo "$st" | grep "^nothing to") ]] && color="$blue1"
        [[ -n $(echo "$st" | grep "^nothing added") ]] && color="$COLFG256[226]"
        # gitdir=$(git rev-parse --git-dir 2> /dev/null)
        # action=$(VCS_INFO_git_getaction "${gitdir}") && action=${action}
        echo "%{${color}%}${name}%f%b|"
    }

    function ssh_prompt() {
        [[ "$SSH_CLIENT" != "" ]] && echo "%B%{${green1}%} [SSH]%f%b"
    }

    function nspawn_prompt() {
        [[ "$(ip link show host0 2> /dev/null)" != "" ]] && echo "%B%{${green2}%} [CONTAINER]%f%b"
    }

    function root_prompt() {
        [[ "$(whoami)" == "root" ]] && echo "%B%F{red} [POWER]%f%b"
    }

    RPROMPT='[$(current_git_status)%*|Ret:%(?,%{${blue1}%}%?,%F{red}%B%?%b%f)%f]'
    PROMPT='${blue1}[%B${blue2}%n%b${blue1}@%M:${blue3}%~${blue1}]%f$(ssh_prompt)$(nspawn_prompt)$(root_prompt)
%# '
fi
