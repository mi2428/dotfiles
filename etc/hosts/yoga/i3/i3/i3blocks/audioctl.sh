#!/bin/bash -eu
cd $(dirname $0)

pacmd="/usr/bin/pacmd"
device="alsa_output.pci-0000_00_1f.3.analog-stereo"

current=$(pacmd list-sinks | grep -E -o "front-left: [[:digit:]]*" | cut -d ' ' -f 2)

case $1 in
    "mute")
        pacmd list-sinks | grep "muted: yes" &&
            pacmd set-sink-mute $device 0 || pacmd set-sink-mute $device 1
        ;;
    "up")
        setvol=$(($current + 3250))
        (( $setvol >= 65000 )) && setvol=65000
        pacmd set-sink-volume $device $setvol ;;
    "down")
        setvol=$(($current - 3250))
        (( $setvol <= 0 )) && setvol=0
        pacmd set-sink-volume $device $setvol ;;
esac