#!/bin/bash
(( $(pgrep synergys | wc -l) >= 1 )) && echo -e "Running!\n\n#8CFF2D" || echo -e "stopped"
