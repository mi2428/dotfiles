#!/bin/bash

if [[ -z $@ ]]; then
    OPTIONS=""
    for inactive in $(netctl list | grep -v '*' | awk '{print $1}'); do
        description=$(cat /etc/netctl/$inactive | grep "Description" | sed -e "s/^Description='\(.*\)'$/\1/")
        profile=$(printf "%-16s" $inactive)
        if [[ $OPTIONS == "" ]]; then
            OPTIONS="$profile\"$description\""
        else
            OPTIONS="$OPTIONS\n$profile\"$description\""
        fi
    done
    active=$(netctl list | grep '*' | awk '{print $2}')
    if [[ $active != "" ]]; then
        description=$(cat /etc/netctl/$active | grep "Description" | sed -e "s/^Description='\(.*\)'$/\1/")
        profile=$(printf "%-16s" "$active*")
        OPTIONS="$profile\"$description\"\n$OPTIONS"
    fi
    echo -e "$OPTIONS"
else
    PROFILE=$(echo $@ | awk '{print $1}' | sed -e "s/\(.*\)\*/\1/g")
    if netctl is-active "$PROFILE" 1> /dev/null 2> /dev/null; then
        exec sudo netctl stop "$PROFILE" 1> /dev/null 2> /dev/null &
    else
        sudo rmmod wl && sudo modprobe wl && \
        exec sudo netctl switch-to "$PROFILE" 1> /dev/null 2> /dev/null &
    fi
fi
