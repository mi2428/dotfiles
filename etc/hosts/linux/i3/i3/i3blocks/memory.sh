#!/bin/bash
echo $(free -h | \grep Mem | awk '{print $3}')
