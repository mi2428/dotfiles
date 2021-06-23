#!/bin/bash
ADDR=$(ip addr show | grep "eth0:" -A 5 | grep "scope global" | grep -v "inet6" | awk '{print $2}')
if [[ "$ADDR" == "" ]]; then
    echo -e "N/A\n\n#FE2E2E"
else
    echo -e "${ADDR}\n\n#8CFF2D"
fi
