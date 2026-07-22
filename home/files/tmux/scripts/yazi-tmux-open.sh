#!/bin/sh
# Route a Yazi popup selection back to the pane that opened it.

set -eu

if [ "$#" -ne 2 ]; then
  printf 'usage: %s PANE_ID FILE\n' "$0" >&2
  exit 2
fi

source_pane=$1
selected=$2
PATH="${HOME}/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
export PATH

tmux_bin=${TMUX_BIN:-tmux}
open_bin=${YAZI_OPEN_BIN:-/usr/bin/open}

case "$source_pane" in
  %*) ;;
  *)
    printf 'yazi-tmux-open: expected a tmux pane id, got %s\n' "$source_pane" >&2
    exit 2
    ;;
esac

mime=$(file -b --mime-type -- "$selected" 2>/dev/null || true)
encoding=$(file -b --mime-encoding -- "$selected" 2>/dev/null || true)
if [ "$mime" != "inode/x-empty" ] && { [ -z "$encoding" ] || [ "$encoding" = "binary" ]; }; then
  "$open_bin" "$selected"
  exit 0
fi

session=$("$tmux_bin" display-message -p -t "$source_pane" '#{session_name}')
source_dir=$("$tmux_bin" display-message -p -t "$source_pane" '#{pane_current_path}')
pane_pid=$("$tmux_bin" display-message -p -t "$source_pane" '#{pane_pid}')
pane_tty=$("$tmux_bin" display-message -p -t "$source_pane" '#{pane_tty}')

tmux_environment() {
  line=$("$tmux_bin" show-environment -t "$session" "$1" 2>/dev/null || true)
  case "$line" in
    "$1="*) printf '%s\n' "${line#*=}" ;;
  esac
}

server=$("$tmux_bin" show-option -wqv -t "$source_pane" @work_nvim_server 2>/dev/null || true)
nvim_pane=$("$tmux_bin" show-option -wqv -t "$source_pane" @work_nvim_pane 2>/dev/null || true)

# Fall back for work sessions created before workspace metadata became
# window-local. This can be removed once those sessions no longer exist.
if [ -z "$server" ]; then
  server=$(tmux_environment NVIM_WORKSPACE_SERVER)
fi
if [ -z "$nvim_pane" ]; then
  nvim_pane=$(tmux_environment NVIM_WORKSPACE_PANE)
fi

tty_name=${pane_tty#/dev/}
foreground_pgid=$(ps -o tpgid= -t "$tty_name" 2>/dev/null | awk 'NF { print $1; exit }')
source_command=$(ps -axo pid=,ppid=,pgid=,tpgid=,stat=,comm= | awk -v root="$pane_pid" '
  {
    pid[NR] = $1
    parent[NR] = $2
    pgid[NR] = $3
    tpgid[NR] = $4
    state[NR] = $5
    command[NR] = $6
    sub(/^.*\//, "", command[NR])
  }
  END {
    descendant[root] = 1
    for (pass = 1; pass <= NR; pass++) {
      for (i = 1; i <= NR; i++) {
        if (descendant[parent[i]]) descendant[pid[i]] = 1
      }
    }
    for (i = 1; i <= NR; i++) {
      if (descendant[pid[i]] && pgid[i] == tpgid[i] && state[i] !~ /^T/ &&
          (command[i] == "nvim" || command[i] == "vim" || command[i] == "vi")) {
        print command[i]
        exit
      }
    }
  }
')

if [ -z "$source_command" ] && [ -n "$foreground_pgid" ]; then
  source_command=$(ps -o pgid=,comm= -t "$tty_name" 2>/dev/null | awk -v pgid="$foreground_pgid" '
    $1 == pgid {
      $1 = ""
      sub(/^ +/, "")
      sub(/^.*\//, "")
      split($0, parts, " ")
      command = parts[1]
      if (command == "nvim" || command == "vim" || command == "vi") {
        print command
        found = 1
        exit
      }
      if (command == "fish" || command == "zsh" || command == "bash" ||
          command == "sh" || command == "dash" || command == "ksh" || command == "nu") {
        if (shell == "") shell = command
      } else {
        nonshell = command
      }
    }
    END {
      if (!found && nonshell != "") print nonshell
      else if (!found) print shell
    }
  ')
fi

if [ -n "$server" ] && [ "$source_pane" = "$nvim_pane" ] && [ -S "$server" ]; then
  if nvim --server "$server" --remote "$selected"; then
    "$tmux_bin" select-pane -t "$source_pane"
    exit 0
  fi
fi

pane_server=$("$tmux_bin" show-option -pqv -t "$source_pane" @yazi_nvim_server 2>/dev/null || true)
if [ -n "$pane_server" ] && [ -S "$pane_server" ]; then
  if nvim --server "$pane_server" --remote "$selected"; then
    "$tmux_bin" select-pane -t "$source_pane"
    exit 0
  fi
  "$tmux_bin" set-option -pu -t "$source_pane" @yazi_nvim_server
fi

shell_quote() {
  escaped=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
  printf "'%s'" "$escaped"
}

new_server() {
  pane_number=${1#%}
  printf '/tmp/tmux-yazi-nvim-%s-%s-%s.sock' "$(id -u)" "$pane_number" "$$"
}

open_in_split() {
  split_server=$(new_server "$source_pane")
  nvim_command="nvim --listen $(shell_quote "$split_server") -- $(shell_quote "$selected")"
  split_pane=$("$tmux_bin" split-window -h -P -F '#{pane_id}' -t "$source_pane" -c "$source_dir" "$nvim_command")
  "$tmux_bin" set-option -p -t "$split_pane" @yazi_nvim_server "$split_server"
}

case "$source_command" in
  nvim|vim|vi)
    open_in_split
    ;;
  fish|zsh|bash|sh|dash|ksh|nu)
    pane_server=$(new_server "$source_pane")
    nvim_command="nvim --listen $(shell_quote "$pane_server") -- $(shell_quote "$selected")"
    "$tmux_bin" set-option -p -t "$source_pane" @yazi_nvim_server "$pane_server"
    "$tmux_bin" send-keys -t "$source_pane" -l "$nvim_command"
    "$tmux_bin" send-keys -t "$source_pane" Enter
    "$tmux_bin" select-pane -t "$source_pane"
    ;;
  *)
    open_in_split
    ;;
esac
