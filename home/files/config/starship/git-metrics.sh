#!/bin/bash
set -euo pipefail

exec python3 "$HOME/.config/starship/git-metrics.py" "$@"
