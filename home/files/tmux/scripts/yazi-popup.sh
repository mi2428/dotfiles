#!/bin/sh
# Browse with Yazi's normal UI and route file selections from the focused pane.

set -eu

if [ "$#" -ne 1 ]; then
  printf 'usage: %s PANE_ID\n' "$0" >&2
  exit 2
fi

source_pane=$1
case "$source_pane" in
  %*) ;;
  *)
    printf 'yazi-popup: expected a tmux pane id, got %s\n' "$source_pane" >&2
    exit 2
    ;;
esac

PATH="${HOME}/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
export PATH

tmux_bin=${TMUX_BIN:-tmux}
current_dir=$("$tmux_bin" display-message -p -t "$source_pane" '#{pane_current_path}')

TMUX_YAZI_SOURCE_PANE=$source_pane
YAZI_TMUX_OPEN=${YAZI_TMUX_OPEN:-"$HOME/.tmux/scripts/yazi-tmux-open.sh"}
YAZI_POPUP=1
export TMUX_YAZI_SOURCE_PANE YAZI_TMUX_OPEN YAZI_POPUP

yazi "$current_dir"
