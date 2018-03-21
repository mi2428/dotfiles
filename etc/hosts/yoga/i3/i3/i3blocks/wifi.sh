#!/bin/bash
declare -r INTERFACE="wlp4s0"

st="$(iwconfig)"
bssid="$(echo $st | grep -A 1 $INTERFACE | grep -E -o '[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}')"
[[ -z "$bssid" ]] && echo -e "N/A\n\n#FE2E2E" && exit 0

essid="$(echo $st | grep $INTERFACE | sed -e "s/^.*ESSID:\"\([^\"]*\).*$/\1/g")"
# quality="$(echo $st | grep -A 5 $INTERFACE | sed -e "s/^.*Link Quality=\([0-9]*\/[0-9]*\).*$/\1/g")"
quality="$(echo $st | grep -A 5 $INTERFACE | sed -e "s/^.*Link Quality=\([0-9]*\)\/.*$/\1/g")%"
ip="$(ip addr show dev $INTERFACE | grep "scope global" | grep -v "inet6" | sed -e "s/^.* inet \(\S*\) .*$/\1/g")"

if [[ -z "$ip" ]]; then 
    echo -e "No Address | $essid | $quality\n\n#FFFF00"
else
    if [[ -n "$(ip route show | head -n 1 | grep $INTERFACE)" ]]; then
        echo -e " $ip (route) | $essid | $quality\n\n#8CFF2D"
    else
        echo -e "$ip | $essid | $quality\n\n#8CFF2D"
    fi
fi
