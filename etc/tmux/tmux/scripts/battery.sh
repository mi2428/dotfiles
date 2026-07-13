#!/bin/zsh

case "$(uname -s)" in
Darwin)
  percent=$(pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | head -n 1)
  ;;
Linux)
  percent=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n 1)
  [[ -n "$percent" ]] && percent="${percent}%"
  ;;
*)
  percent=""
  ;;
esac

if [[ -n "$percent" ]]; then
  printf '%s\n' "$percent"
else
  printf 'AC\n'
fi
