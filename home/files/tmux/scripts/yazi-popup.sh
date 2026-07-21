#!/bin/sh
# Browse from the focused pane and route selected files to the right opener.

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
session=$("$tmux_bin" display-message -p -t "$source_pane" '#{session_name}')
current_dir=$("$tmux_bin" display-message -p -t "$source_pane" '#{pane_current_path}')

tmux_environment() {
  line=$("$tmux_bin" show-environment -t "$session" "$1" 2>/dev/null || true)
  case "$line" in
    "$1="*) printf '%s\n' "${line#*=}" ;;
  esac
}

server=$(tmux_environment NVIM_WORKSPACE_SERVER)
nvim_pane=$(tmux_environment NVIM_WORKSPACE_PANE)
YAZI_POPUP=1
export YAZI_POPUP

runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/tmux-yazi.XXXXXXXX")
chooser=$runtime_dir/chooser

cleanup() {
  rm -rf -- "$runtime_dir"
}
trap cleanup EXIT HUP INT TERM

yazi "$current_dir" --chooser-file="$chooser"

if [ ! -s "$chooser" ]; then
  exit 0
fi

# Outside a work session, hand selections to the macOS default application.
if [ -z "$server" ]; then
  selected=
  while IFS= read -r selected || [ -n "$selected" ]; do
    [ -n "$selected" ] || continue
    /usr/bin/open "$selected"
  done <"$chooser"
  exit 0
fi

attempt=0
while [ "$attempt" -lt 50 ] && [ ! -S "$server" ]; do
  attempt=$((attempt + 1))
  sleep 0.1
done

if [ ! -S "$server" ]; then
  printf 'yazi-popup: Neovim server is not available: %s\n' "$server" >&2
  sleep 1
  exit 1
fi

selected=
while IFS= read -r selected || [ -n "$selected" ]; do
  [ -n "$selected" ] || continue
  nvim --server "$server" --remote "$selected"
done <"$chooser"

if [ -n "$nvim_pane" ]; then
  "$tmux_bin" select-pane -t "$nvim_pane"
fi
