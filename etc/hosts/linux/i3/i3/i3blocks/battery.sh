#!/bin/bash
STATUS=`cat /sys/class/power_supply/BAT0/status`
REMAIN=$(echo "scale=1; `cat /sys/class/power_supply/BAT0/capacity`*100/97" | bc -l)
if [ ${STATUS} = "Discharging" ]; then
    remain=$(( `echo $REMAIN | sed -e 's/\.[0-9]*$'//g` + 0))
    if [ $remain -ge 60 ]; then
        # echo -e "${STATUS} ${REMAIN}%\n\n#BFFF00"
        echo -e "${STATUS} ${REMAIN}%\n\n#8CFF2D"
    elif [ $remain -ge 20 ]; then
        echo -e "${STATUS} ${REMAIN}%\n\n#FFFF00"
    else
        echo -e "${STATUS} ${REMAIN}%\n\n#FE2E2E"
    fi
else
    # echo -e "${STATUS} ${REMAIN}%\n\n#BFFF00"
    echo -e "${STATUS} ${REMAIN}%\n\n#8CFF2D"
fi
