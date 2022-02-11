#!/bin/bash
set -e
cd $HOME

declare -r TERMINAL="$(which mlterm) -#"

_rofi() {
    rofi -dmenu -width 1120 -lines 20 "$@"
}

rofi_menu() {
    local mesg="$1" entries="$2" prompt="$3"
    printf "$(printf "$entries" | _rofi -mesg "$mesg" -p "$prompt")"
}


server-list() {
    while read host; do
        [[ "$host" = "github.com" ]] && continue
        [[ "$host" = "gitlab.i.mi2428.net" ]] && continue
        host="@$host"
        printf "[=] $host\n"
    done < <(grep -e '^Host' $HOME/.ssh/config | awk '{print $NF}')
}

session-list() {
    local host=$1 sessions="tmux list-sessions"
    [[ -n "$host" ]] && sessions="ssh $host $sessions"
    while read session; do
        printf "[#] $session\n"
    done < <($sessions | sort -n)
}

create() {
    local host=$1
    [[ -z "$host" ]] && \
    $TERMINAL "tmux new-session\n" || \
    $TERMINAL "ssh -Y -t $host \"tmux new-session\"\n"
}

attach() {
    local host=$1 session=$2
    [[ -z "$host" ]] && \
    $TERMINAL "tmux attach-session -t $session\n" || \
    $TERMINAL "ssh -Y -t $host \"tmux attach-session -t $session\"\n"
}

main() {
    local host="$1" menu option session attach create
    menu="[+] Create new session\n"
    menu+="$(session-list $host)\n"
    [[ -z "$host" ]] && menu+="$(server-list)"
    option=$(rofi_menu "select tmux session" "$menu" "tmux: ")
    [[ -z "$option" ]] && exit 1

    [[ -z "$host" ]] && \
    host="$(printf "$option" | grep -e '^\[=\] @\(.*\)$' | sed -e 's/^\[=\] @\(.*\)$/\1/g')"
    session="$(printf "$option" | grep -e '^\[#\] \(.*\):.*$' | sed -e 's/^\[#\] \(.*\): [1-9] windows.*$/\1/g')"
    [[ -n "$session" ]] && attach=true || attach=false
    [[ -n "$(printf "$option" | grep -e '\[+\]')" ]] && create=true || create=false

    $create && create "$host" && exit 0
    $attach && attach "$host" "$session" && exit 0
    main "$host"
} && main
