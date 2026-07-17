#!/bin/sh
# Open tmux's complete rendered scrollback for one pane in an editor.
#
# `capture-pane` is intentionally used instead of `pipe-pane`: it snapshots
# exactly the history tmux copy mode can show. It does not try to be a raw
# terminal-output logger, which would disagree with copy mode after terminal
# escape sequences or screen redraws.

set -eu

if [ "$#" -ne 1 ]; then
  printf 'usage: %s PANE_ID\n' "$0" >&2
  exit 2
fi

target_pane=$1
case "$target_pane" in
  %*) ;;
  *)
    printf 'edit-scrollback: expected a tmux pane id, got %s\n' "$target_pane" >&2
    exit 2
    ;;
esac

tmux_bin=${TMUX_BIN:-tmux}
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}
cache_dir="$cache_root/tmux-scrollback"

# Scrollback can contain credentials or serial-console output. Keep snapshots
# private and delete them once the editor exits.
umask 077
mkdir -p "$cache_dir"
chmod 700 "$cache_dir"
snapshot=$(mktemp "$cache_dir/scrollback.XXXXXXXX")

cleanup() {
  rm -f -- "$snapshot"
}
trap cleanup EXIT HUP INT TERM

screen_is_attached_to_target() {
  command -v pgrep >/dev/null 2>&1 || return 1

  pane_tty=$("$tmux_bin" display-message -p -t "$target_pane" "#{pane_tty}" 2>/dev/null) || return 1
  [ -n "$pane_tty" ] || return 1

  # GNU screen's client process keeps the pane's controlling TTY. This avoids
  # sending a screen command to a normal serial-console or SSH pane.
  pgrep -t "${pane_tty#/dev/}" -x screen >/dev/null 2>&1
}

capture_screen_history() {
  # GNU screen owns its own defscrollback while it occupies tmux's alternate
  # screen, so tmux cannot capture those older lines. The managed .screenrc
  # retains screen's default ^A command prefix; hardcopy -h writes the same
  # visible buffer plus screen scrollback without changing the current window.
  rm -f -- "$snapshot"
  screen_snapshot=$(printf '%s' "$snapshot" | sed 's/["\\]/\\&/g')
  "$tmux_bin" send-keys -t "$target_pane" C-a : "hardcopy -h \"$screen_snapshot\"" Enter

  # screen processes the command asynchronously. Wait until its output has
  # stopped growing so the editor never opens a partial serial-console log.
  previous_size=
  stable_samples=0
  attempt=0
  while [ "$attempt" -lt 40 ]; do
    if [ -f "$snapshot" ]; then
      current_size=$(wc -c < "$snapshot" | tr -d '[:space:]')
      if [ "$current_size" = "$previous_size" ]; then
        stable_samples=$((stable_samples + 1))
        if [ "$stable_samples" -ge 2 ]; then
          return 0
        fi
      else
        previous_size=$current_size
        stable_samples=0
      fi
    fi
    attempt=$((attempt + 1))
    sleep 0.05
  done

  return 1
}

# -S - and -E - mean the first and last lines retained by tmux. Leaving out
# -e is intentional: an editor should receive the rendered text, not raw ANSI
# escape sequences which would make its view differ from tmux copy mode.
if ! screen_is_attached_to_target || ! capture_screen_history; then
  "$tmux_bin" capture-pane -p -S - -E - -t "$target_pane" > "$snapshot"
fi

# A single executable path is accepted deliberately; parsing a shell command
# from $EDITOR would turn an environment value into code execution. Set
# TMUX_SCROLLBACK_EDITOR to an explicit editor binary when needed.
editor=${TMUX_SCROLLBACK_EDITOR:-${VISUAL:-${EDITOR:-nvim}}}
"$editor" "$snapshot"
