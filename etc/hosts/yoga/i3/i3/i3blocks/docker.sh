#!/bin/bash
systemctl is-active docker 1>&2 /dev/null && echo -e "Running!\n\n#8CFF2D" || echo -e "stopped"
