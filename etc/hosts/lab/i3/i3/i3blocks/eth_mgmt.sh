#!/bin/bash
ADDR=$(ip addr show | grep "management@eno1" -A 5 | grep "scope global management" | awk '{print $2}')
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
