#!/bin/bash
brightness=$(echo "scale=1; `cat /sys/class/backlight/intel_backlight/brightness`/10" | bc -l)
echo $brightness%
