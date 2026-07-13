#!/bin/zsh

cores="${TMUX_CPU_CORES:-$(sysctl -n hw.logicalcpu 2>/dev/null)}"
load_avg="$(uptime | awk '{gsub(/,/, "", $(NF-2)); print $(NF-2)}')"

if [[ -z "$cores" || "$cores" == "0" || -z "$load_avg" ]]; then
  printf '0%%\n'
  exit 0
fi

printf '%.0f%%\n' $((100 * load_avg / cores))
