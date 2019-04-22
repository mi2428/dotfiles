#!/bin/bash -eu
cd $(dirname $0)

pacmd="/usr/bin/pacmd"
device=$(pacmd list-sinks | grep alsa_output | cut -d ' ' -f 2 | sed -e 's/>//g' -e 's/<//g')

current=$(pacmd list-sinks | grep -E -o "front-left: [[:digit:]]*" | cut -d ' ' -f 2)

case $1 in
    "mute")
        pacmd list-sinks | grep "muted: yes" &&
            pacmd set-sink-mute $device 0 || pacmd set-sink-mute $device 1
        ;;
    "up")
        setvol=$(($current + 5000))
        (( $setvol >= 65000 )) && setvol=65000
        pacmd set-sink-volume $device $setvol ;;
    "down")
        setvol=$(($current - 5000))
        (( $setvol <= 0 )) && setvol=0
        pacmd set-sink-volume $device $setvol ;;
esac
