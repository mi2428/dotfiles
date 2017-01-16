#!/bin/bash
USB_INTERFACE=$(ip link show | grep -o "wlp0s20u[1-2]")
INTERFACE=${USB_INTERFACE:-wlp30}
ESSID=$(iw dev "$INTERFACE" link | grep "SSID" | awk '{print $2}')
if [ "$ESSID" == "" ]; then
    # echo -e "Not-Associated\n\n#FE2E2E"
    echo -e "N/A\n\n#FE2E2E"
else
    SIGNAL=$(sudo iw dev $INTERFACE link | grep "signal" | awk '{print $2,$3}')
    RATE=$(sudo iw dev $INTERFACE link | grep "bitrate" | awk '{print $3,$4}')
    IP=$(ip addr show | grep "$INTERFACE" | grep "inet" | awk '{print $2}')
    if [ "$IP" == "" ]; then 
        echo  -e "No Address | $ESSID | $SIGNAL\n\n#FFFF00"
    else
        if [[ $(ip route show | sed -n '1,1p' | grep $INTERFACE) != "" ]]; then
            echo  -e " $IP (route) | $ESSID | $SIGNAL\n\n#8CFF2D"
        else
            echo  -e "$IP | $ESSID | $SIGNAL\n\n#8CFF2D"
        fi
    fi
fi
