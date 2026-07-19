#!/bin/sh
# Launch lazygit with the same popup-only configuration used by Herdr.

set -eu

# A tmux server started by a GUI app can retain a minimal PATH. Include the
# managed Nix profile and Homebrew locations before looking up fish or lazygit.
PATH="${HOME}/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
export PATH

if command -v fish >/dev/null 2>&1; then
  # Run the assignment after fish has loaded its startup configuration so the
  # popup augments, rather than replaces, the regular Catppuccin merge config.
  # shellcheck disable=SC2016 # Variables expand inside fish, not this shell.
  exec fish -lc 'set -lx LG_CONFIG_FILE "$LG_CONFIG_FILE,$HOME/.config/herdr/lazygit-unified.yml"; exec lazygit'
fi

popup_config="${HOME}/.config/herdr/lazygit-unified.yml"
if [ -n "${LG_CONFIG_FILE:-}" ]; then
  export LG_CONFIG_FILE="${LG_CONFIG_FILE},${popup_config}"
else
  export LG_CONFIG_FILE="$popup_config"
fi

exec lazygit
