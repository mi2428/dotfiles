#!/bin/bash
VOL=`pulseaudio-ctl current`
MUTE=`pulseaudio-ctl full-status | awk '{print $2}'`
if [ "$MUTE" = "yes" ]; then
    echo -n "$VOL (muted)"
else
    echo -n "$VOL"
fi
