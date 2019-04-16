#!/bin/bash -eu
cd $(dirname $0)

pacmd="/usr/bin/pacmd"
device="alsa_output.pci-0000_04_00.1.hdmi-stereo-extra2"

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
