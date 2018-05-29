#!/bin/bash
INTERFACES=$(ip link show | grep "state UP" | awk '{print $2}' | grep -E "^e.*$" | tr -d ':')
if [[ -z $INTERFACES ]]; then
    echo -e "N/A\n\n#FE2E2E"
else
    IP=""
    for interface in ${INTERFACES[@]}; do
        ipaddr=$(ip addr show dev $interface | grep -E -o '([[:digit:]]{1,3}.){3}[[:digit:]]{1,3}/[[:digit:]]{1,2}' | tr '\n' ' ')
        IP="$ipaddr $IP"
    done
    echo -e "${IP}\n\n#8CFF2D"
fi
