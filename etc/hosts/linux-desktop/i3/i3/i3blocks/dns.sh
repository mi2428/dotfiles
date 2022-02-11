#!/bin/bash
dns=$(cat /etc/resolv.conf | grep -v "#" | grep "nameserver" | head -n 1 | awk '{print $NF}')
[[ $dns != "" ]] && echo -e "$dns\n\n#8CFF2D" || echo -e "N/A\n\n#FE2E2E"
