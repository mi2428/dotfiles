#!/bin/bash
set -eu
cd $(dirname $0)

(( $EUID > 0 )) && sudo $0 $@ && exit 0

declare -r KBDBACKLIGHT="/sys/devices/platform/thinkpad_acpi/leds/tpacpi::kbd_backlight/brightness"
declare -r current=$(cat $KBDBACKLIGHT)

case $1 in
    "up")
        echo $(($current + 1)) > $KBDBACKLIGHT ;;
    "down")
        echo $(($current - 1)) > $KBDBACKLIGHT ;;
esac
