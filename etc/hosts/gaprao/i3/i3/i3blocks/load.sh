#!/bin/bash
load=$(cut -d ' ' -f3 /proc/loadavg)
echo $load
