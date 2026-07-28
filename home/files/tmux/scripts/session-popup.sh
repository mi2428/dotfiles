#!/bin/sh
# Select a tmux session in fzf and move the invoking client to it.

set -eu

# A tmux server started by a GUI app can retain a minimal PATH.
PATH="${HOME}/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
export PATH

tmux_bin=${TMUX_BIN:-tmux}

if ! command -v fzf >/dev/null 2>&1; then
  "$tmux_bin" display-message "session switcher: fzf is not installed"
  exit 127
fi

selected=$(
  "$tmux_bin" list-sessions \
    -F '#{session_id}  #{session_name}  (#{session_windows} windows, #{?session_attached,attached,detached})' |
    env NO_COLOR= TMUX_BIN="$tmux_bin" fzf \
      --layout=reverse \
      --info=inline \
      --no-multi \
      --prompt='session> ' \
      --preview="\"\$TMUX_BIN\" capture-pane -e -p -t {1}" \
      --preview-window='right,60%,border-left'
) || exit 0

[ -n "$selected" ] || exit 0

# The stable session id is the first field, so names containing spaces remain
# unambiguous. switch-client is tmux's in-server detach/attach operation.
session_id=${selected%% *}
"$tmux_bin" switch-client -t "$session_id"
