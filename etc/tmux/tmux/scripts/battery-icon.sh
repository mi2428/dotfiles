#!/bin/zsh

battery_tier_icon() {
  local percent="$1"

  if (( percent >= 95 )); then
    echo "󰁹"
  elif (( percent >= 85 )); then
    echo "󰂂"
  elif (( percent >= 75 )); then
    echo "󰂁"
  elif (( percent >= 65 )); then
    echo "󰂀"
  elif (( percent >= 55 )); then
    echo "󰁿"
  elif (( percent >= 45 )); then
    echo "󰁾"
  elif (( percent >= 35 )); then
    echo "󰁽"
  elif (( percent >= 25 )); then
    echo "󰁼"
  elif (( percent >= 15 )); then
    echo "󰁻"
  elif (( percent > 0 )); then
    echo "󰁺"
  else
    echo "󰂎"
  fi
}

case "$(uname -s)" in
Darwin)
  line=$(pmset -g batt 2>/dev/null | sed -n '2p')
  percent=$(printf '%s\n' "$line" | grep -Eo '[0-9]+%' | head -n 1 | tr -d '%')

  if [[ "$line" == *"charging"* ]]; then
    echo "󰂄"
  elif [[ "$line" == *"charged"* ]] || [[ "$line" == *"AC Power"* && "$percent" == "100" ]]; then
    echo "󰚥"
  elif [[ -n "$percent" ]]; then
    battery_tier_icon "$percent"
  else
    echo "󰂑"
  fi
  ;;
Linux)
  battery_dir=$(echo /sys/class/power_supply/BAT* 2>/dev/null | awk '{print $1}')
  if [[ -d "$battery_dir" ]]; then
    percent=$(cat "$battery_dir/capacity" 2>/dev/null)
    status=$(cat "$battery_dir/status" 2>/dev/null)

    if [[ "$status" == "Charging" ]]; then
      echo "󰂄"
    elif [[ "$status" == "Full" ]]; then
      echo "󰚥"
    elif [[ -n "$percent" ]]; then
      battery_tier_icon "$percent"
    else
      echo "󰂑"
    fi
  else
    echo "󰚥"
  fi
  ;;
*)
  echo "󰂑"
  ;;
esac
