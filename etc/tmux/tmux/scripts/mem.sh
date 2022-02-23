#!/bin/zsh
used=$(free | grep "Mem:" | awk '{print 100*$3/$2}')
printf '%.0f%%\n' $used
