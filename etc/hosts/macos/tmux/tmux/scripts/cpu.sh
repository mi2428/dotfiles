#!/bin/zsh
ncpus=10
printf '%.0f%%\n' $(( 100 * $(w | head -n 1 | awk '{print $(NF-2)}') / $ncpus ))
