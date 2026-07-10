#!/bin/bash
set -euo pipefail

FISH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
FISH_PLUGINS_FILE="$FISH_CONFIG_DIR/fish_plugins"

if ! command -v fish >/dev/null 2>&1; then
  exit 0
fi

if [[ ! -f "$FISH_PLUGINS_FILE" ]]; then
  exit 0
fi

if ! fish -c 'type -q fisher' >/dev/null 2>&1; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "setup-fish-plugins: curl is required to bootstrap fisher." >&2
    exit 1
  fi
  fish -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source; fisher install jorgebucaran/fisher'
fi

fish -c 'fisher update'
