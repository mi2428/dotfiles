#!/bin/bash
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

exec python3 "$config_home/starship/git-metrics.py" "$@"
