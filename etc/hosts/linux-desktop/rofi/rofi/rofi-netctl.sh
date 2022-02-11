#!/bin/bash

args="$@"
options=""

add_option() {
    local profile="$1" prefix="$2" description
    _file="/etc/netctl/$profile"
    description="$(grep "Description" $_file | sed -e "s/Description='\([^']*\)'/\1/g")"
    [[ -n $options ]] && options="$prefix$profile\t\"$description\"\n$options" || options="$prefix$profile\t\"$description\""
}

if [[ -z "$args" ]]; then
    for profile in $(netctl list | grep -v '*' | tr -d ' '); do
        add_option "$profile"
    done
    active="$(netctl list | grep '*' | tr -d '*' | tr -d ' ')"
    [[ -n "$active" ]] && add_option "$active" "!"
    echo -e $options | expand -t 16
else
    profile=$(echo $args | tr -d '!' | awk '{print $1}')
    if netctl is-active "$profile" 2> /dev/null 1>&2; then
        sudo netctl stop "$profile" 2> /dev/null 1>&2 &
    else
        sudo netctl switch-to "$profile" 2> /dev/null 1>&2 &
    fi
fi
