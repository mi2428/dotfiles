#!/bin/bash
gw=$(ip route show | grep "default" | sed -n 1p | sed -e 's/^.*via \(\S*\).*$/\1/g')
[[ $gw != "" ]] && echo -e "$gw\n\n#8CFF2D" || echo -e "N/A\n\n#FE2E2E"
