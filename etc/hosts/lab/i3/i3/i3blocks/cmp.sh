#!/bin/bash
compton=$(pgrep compton)
[[ $compton != "" ]] && echo -e "Running!\n\n#8CFF2D" || echo -e "stopped"
