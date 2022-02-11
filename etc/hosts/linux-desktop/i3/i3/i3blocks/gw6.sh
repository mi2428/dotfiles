#!/bin/bash

#gw=$(ip -6 route show default | sed -n 1p | sed -e 's/^.*via \(\S*\).*$/\1/g')
gw=$(ip -6 r show default | grep via | cut -d " " -f 3 | sed -n 1p)
[[ $gw != "" ]] && echo -e "$gw\n\n#8CFF2D" || echo -e "N/A\n\n#FE2E2E"
