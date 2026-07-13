#!/bin/zsh

used_percent="$(free | awk '/^Mem:/ {print 100 * $3 / $2; exit}')"

if [[ -z "$used_percent" ]]; then
  printf '0%%\n'
  exit 0
fi

printf '%.0f%%\n' "$used_percent"
