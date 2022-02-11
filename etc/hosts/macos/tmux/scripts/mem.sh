#!/bin/zsh
free=$(memory_pressure | grep "System-wide memory free percentage:" | \grep -Eo '[0-9]*')
printf '%.0f%%\n' $(( 100 - free ))
