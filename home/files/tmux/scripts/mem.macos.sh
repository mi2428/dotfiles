#!/bin/zsh

free_percent="$(memory_pressure 2>/dev/null | awk -F': ' '/System-wide memory free percentage:/ {gsub(/%/, "", $2); print $2; exit}')"

if [[ -z "$free_percent" ]]; then
  printf '0%%\n'
  exit 0
fi

printf '%.0f%%\n' $((100 - free_percent))
