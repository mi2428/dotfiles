#!/usr/bin/env bash

cores="${TMUX_CPU_CORES:-$(nproc 2>/dev/null || lscpu | awk '/^CPU\\(s\\):/ {print $2; exit}')}"
load_avg="$(uptime | awk '{print $NF}')"

if [[ -z "$cores" || "$cores" == "0" || -z "$load_avg" ]]; then
  printf '0%%\n'
  exit 0
fi

awk -v avg="$load_avg" -v cores="$cores" 'BEGIN { printf "%.0f%%\n", 100 * avg / cores }'
