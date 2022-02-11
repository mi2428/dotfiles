#!/bin/zsh
w | head -n 1 | awk '{print $4}'
