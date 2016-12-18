#!/bin/bash
INTERFACE="enp0s20u1"
# INTERFACE="enp0s20u2"
ADDR=$(ip addr show dev $INTERFACE | grep "global $INTERFACE" | awk '{print $2}')
if [[ "$ADDR" == "" ]]; then
    echo -e "Not-Connected\n\n#FE2E2E"
else
    if [[ $(ip route show | sed -n '1,1p' | grep "$INTERFACE") != "" ]]; then
        echo -e "${ADDR} (Default)\n\n#8CFF2D"
    else
        echo -e "${ADDR}\n\n#8CFF2D"
    fi
fi
