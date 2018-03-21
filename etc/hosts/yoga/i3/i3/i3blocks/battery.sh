#!/bin/bash
STATUS=$(cat /sys/class/power_supply/BAT0/status)
REMAIN=$(echo "scale=1; $(cat /sys/class/power_supply/BAT0/capacity)*100/86" | bc -l)
LOG="/tmp/i3blocks-battery.log"

if [[ -f $NOTIFY ]]; then
    st=$(cat $LOG | cut -d : -f 1)
    rem=$(cat $LOG | cut -d : -f 2)
    notified=$(cat $LOG | cut -d : -f 3)
    if (( $notified < 1 )) && [[ $STATUS = "Discharging" ]] && (( $remain < 20 )); then
        notify-send -u critical "LOW BATTERY WARNING" "battery < 20%" && notified=1
    elif (( $notified < 1 )) && [[ $STATUS = "Charging" ]] && [[ $st = "Discharging" ]]; then
        notify-send "BATTERY INFORMATION" "charging..." && notified=1
    fi
else
    notified=0
fi

echo "${STATUS}:${REMAIN}:${notified}" > $LOG
if [[ ${STATUS} = "Discharging" ]]; then
    remain=$(( $(echo $REMAIN | sed -e 's/\.[0-9]*$'//g) + 0 ))
    (( $remain > 60 )) && echo -e "${STATUS} ${REMAIN}%\n\n#8CFF2D" || \
    (( $remain > 20 )) && echo -e "${STATUS} ${REMAIN}%\n\n#FFFF00" || \
    echo -e "${STATUS} ${REMAIN}%\n\n#FE2E2E"
else
    echo -e "${STATUS} ${REMAIN}%\n\n#8CFF2D"
    notified=0
fi
