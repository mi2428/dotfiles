#!/bin/zsh
w | tail -n +3 | awk '{print $1}' | sort | uniq | wc -l
