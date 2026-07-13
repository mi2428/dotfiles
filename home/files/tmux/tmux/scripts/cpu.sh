#!/bin/zsh
cpucore=$(lscpu | grep -o '^CPU(s):.*\([0-9]\)$' | awk '{print $NF}')
printf '%.0f%%\n' $(( 100 * $(w | head -n 1 | awk '{print $NF}') / $cpucore ))
