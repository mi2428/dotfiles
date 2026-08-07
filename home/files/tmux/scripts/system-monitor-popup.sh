#!/bin/sh
# Launch the best available interactive system monitor.

set -eu

# A tmux server started by a GUI app can retain a minimal PATH.
PATH="${HOME}/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
export PATH

for monitor in btop htop top; do
  if command -v "$monitor" >/dev/null 2>&1; then
    exec "$monitor"
  fi
done

printf '%s\n' 'system monitor: btop, htop, and top are not installed' >&2
exit 127
