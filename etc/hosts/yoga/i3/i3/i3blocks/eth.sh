#!/bin/bash
INTERFACE=$(ip link show | grep -m 1 -o "enp0s31f6")
ADDR=$(ip addr show dev $INTERFACE | grep "global" | awk '{print $2}')
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
