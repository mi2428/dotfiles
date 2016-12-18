#!/bin/bash
INTERFACE=$(ip link show | grep -o "enp0s20u[1-2]")
ADDR=$(ip addr show dev $INTERFACE | grep "global $INTERFACE" | awk '{print $2}')
if [[ "$ADDR" == "" ]]; then
    # echo -e "Not-Connected\n\n#FE2E2E"
    echo -e "N/A\n\n#FE2E2E"
else
    if [[ $(ip route show | sed -n '1,1p' | grep $INTERFACE) != "" ]]; then
        echo -e "${ADDR} (route)\n\n#8CFF2D"
    else
        echo -e "${ADDR}\n\n#8CFF2D"
    fi
fi
