#!/bin/zsh
total=$(diskutil info /dev/disk3s1s1 | grep "Container Total Space:" | sed 's/^.*(exactly \([0-9]*\) 512-Byte-Units)$/\1/')
avail=$(diskutil info /dev/disk3s1s1 | grep "Container Free Space:" | sed 's/^.*(exactly \([0-9]*\) 512-Byte-Units)$/\1/')
printf '%.0f%%\n' $(( 100 * (total - avail) / total ))
