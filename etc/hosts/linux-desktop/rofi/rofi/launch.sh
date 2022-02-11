#!/bin/bash
SCRIPTS="netctl:~/.rofi/rofi-netctl.sh,power:~/.rofi/rofi-power.sh"
exec rofi -modi "$SCRIPTS" -combi-modi "$SCRIPTS" -show combi -terminal mlterm -location 0 -sidebar-mode
