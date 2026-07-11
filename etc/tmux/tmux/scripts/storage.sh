#!/bin/zsh
used=$(df -Pk / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
printf '%s%%\n' "${used:-0}"
