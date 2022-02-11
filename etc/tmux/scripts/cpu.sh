#!/bin/zsh
printf '%.0f%%\n' $(( 100 * $(w | head -n 1 | awk '{print $NF-2}') / 8 ))
