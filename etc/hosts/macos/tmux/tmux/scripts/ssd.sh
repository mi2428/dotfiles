#!/bin/zsh
diskname=$(df / | sed -n 2,2p | cut -d ' ' -f 1)
total=$(diskutil info $diskname | grep "Container Total Space:" | sed 's/^.*(exactly \([0-9]*\) 512-Byte-Units)$/\1/')
avail=$(diskutil info $diskname | grep "Container Free Space:" | sed 's/^.*(exactly \([0-9]*\) 512-Byte-Units)$/\1/')
printf '%.0f%%\n' $(( 100 * (total - avail) / total ))
