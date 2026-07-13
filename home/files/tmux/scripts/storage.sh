#!/bin/zsh

used_percent="$(df -Pk / | awk 'NR == 2 {gsub(/%/, "", $5); print $5}')"
printf '%s%%\n' "${used_percent:-0}"
