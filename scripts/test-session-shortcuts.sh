#!/bin/sh

set -eu

DOTFILES_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
export DOTFILES_ROOT

fish --no-config /dev/stdin <<'FISH'
cd "$DOTFILES_ROOT"
source home/files/config/fish/conf.d/21_functions.fish

function tmux
    if test (count $argv) -eq 3; and test "$argv[1]" = list-sessions; and test "$argv[2]" = -F
        printf '%s\n' existing config
        return 0
    end

    printf 'tmux'
    for arg in $argv
        printf '|%s' "$arg"
    end
    printf '\n'
end

function herdr
    set -l command_line (string join ' ' -- $argv)
    set -ga __test_herdr_calls "$command_line"
    if test "$command_line" = 'session list --json'
        printf '%s\n' '{"sessions":[{"name":"default","running":true},{"name":"stopped","running":false}]}'
        return 0
    end

    printf 'herdr'
    for arg in $argv
        printf '|%s' "$arg"
    end
    printf '\n'
end

function assert_equal --argument-names label expected actual
    if test "$expected" != "$actual"
        printf 'fish: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    end
end

assert_equal 'tmux attach dispatch failed' 'tmux|attach|-t|existing' (:: existing)
assert_equal 'tmux delete dispatch failed' 'tmux|kill-session|-t|existing' (:: d existing)
assert_equal 'tmux list dispatch failed' 'tmux|list-sessions' (:: l)
assert_equal 'tmux passthrough failed' 'tmux|list-sessions|extra' (:: list-sessions extra)
assert_equal 'Herdr running attach dispatch failed' 'herdr|session|attach|default' (::: default)
assert_equal 'Herdr stopped attach dispatch failed' 'herdr|session|attach|stopped' (::: stopped)
assert_equal 'Herdr passthrough failed' 'herdr|session|list' (::: session list)
assert_equal 'Herdr command passthrough failed' 'herdr|status' (::: status)
assert_equal 'Herdr list dispatch failed' \
    '{"sessions":[{"name":"default","running":true},{"name":"stopped","running":false}]}' \
    (::: l --json)
assert_equal 'Herdr delete dispatch failed' \
    'herdr|session|delete|stopped' \
    (::: d stopped)

set -l current_path (path resolve .)
assert_equal 'tmux named session creation failed' \
    "tmux|new-session|-s|named|-c|$current_path" \
    (:: c named)
assert_equal 'Herdr named session creation failed' 'herdr|--session|named' (::: c named)
assert_equal 'tmux long create dispatch failed' \
    "tmux|new-session|-s|long-named|-c|$current_path" \
    (:: create long-named)
assert_equal 'Herdr long create dispatch failed' 'herdr|--session|long-named' (::: create long-named)

set -l config_path (path resolve home/files/config)
assert_equal 'tmux default-target workspace dispatch failed' \
    "tmux|new-window|-c|$config_path" \
    (:: n home/files/config)
assert_equal 'tmux explicit-target workspace dispatch failed' \
    "tmux|new-window|-t|existing|-c|$config_path" \
    (:: n home/files/config existing)

::: n home/files/config
assert_equal 'Herdr workspace creation failed' 0 $status
assert_equal 'Herdr workspace default target failed' \
    "--session default workspace create --cwd $config_path --focus" \
    "$__test_herdr_calls[-1]"
::: n home/files/config stopped
assert_equal 'Herdr workspace explicit target failed' \
    "--session stopped workspace create --cwd $config_path --focus" \
    "$__test_herdr_calls[-1]"

:: n >/dev/null 2>/dev/null
assert_equal 'tmux invalid usage status changed' 2 $status
FISH

fish --no-config --interactive /dev/stdin <<'FISH_COMPLETIONS'
cd "$DOTFILES_ROOT"
set -gx DOTFILES_HERDR_PANE_LABEL_WATCHER 1
source home/files/config/fish/conf.d/21_functions.fish

function tmux
    if test (count $argv) -eq 3; and test "$argv[1]" = list-sessions; and test "$argv[2]" = -F
        printf '%s\n' existing config
    end
end

function herdr
    if test (string join ' ' -- $argv) = 'session list --json'
        printf '%s\n' '{"sessions":[{"name":"default","running":true},{"name":"stopped","running":false}]}'
    end
end

source home/files/config/fish/conf.d/23_completions.fish

set -l tmux_completion (string join \t -- existing 'tmux session')
contains -- "$tmux_completion" (complete -C ':: '); or exit 1

set -l running_completion (string join \t -- default 'running Herdr session')
set -l stopped_completion (string join \t -- stopped 'stopped Herdr session')
set -l list_completion (string join \t -- l 'List sessions')
set -l create_completion (string join \t -- c 'Create a named session')
set -l new_completion (string join \t -- n 'Add a work area to a session')
set -l delete_completion (string join \t -- d 'Delete a session')
set -l herdr_completions (complete -C '::: ')
contains -- "$running_completion" $herdr_completions; or exit 1
contains -- "$stopped_completion" $herdr_completions; or exit 1
contains -- "$list_completion" $herdr_completions; or exit 1
contains -- "$create_completion" $herdr_completions; or exit 1
contains -- "$new_completion" $herdr_completions; or exit 1
contains -- "$delete_completion" $herdr_completions; or exit 1
contains -- "$stopped_completion" (complete -C '::: d '); or exit 1
contains -- "$running_completion" (complete -C '::: n home/files/config '); or exit 1
contains -- "$tmux_completion" (complete -C ':: d '); or exit 1
contains -- "$tmux_completion" (complete -C ':: n home/files/config '); or exit 1
contains -- "$create_completion" (complete -C ':: '); or exit 1
contains -- "$new_completion" (complete -C ':: '); or exit 1
exit
FISH_COMPLETIONS

zsh -f /dev/stdin <<'ZSH'
cd "$DOTFILES_ROOT"
source home/files/zsh/20_aliases.zsh

commands[tmux]=/bin/echo
commands[herdr]=/bin/echo
__dotfiles_tmux_session_names() { print -l existing config }
__dotfiles_herdr_session_names() { print -l default stopped }

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    print -u2 -- "zsh: $label"
    print -u2 -- "expected: $expected"
    print -u2 -- "actual:   $actual"
    exit 1
  fi
}

assert_equal 'tmux attach dispatch failed' 'attach -t existing' "$(:: existing)"
assert_equal 'tmux delete dispatch failed' 'kill-session -t existing' "$(:: d existing)"
assert_equal 'tmux list dispatch failed' 'list-sessions' "$(:: l)"
assert_equal 'tmux passthrough failed' 'list-sessions extra' "$(:: list-sessions extra)"
assert_equal 'Herdr running attach dispatch failed' 'session attach default' "$(::: default)"
assert_equal 'Herdr stopped attach dispatch failed' 'session attach stopped' "$(::: stopped)"
assert_equal 'Herdr passthrough failed' 'session list' "$(::: session list)"
assert_equal 'Herdr command passthrough failed' 'status' "$(::: status)"
assert_equal 'Herdr list dispatch failed' 'session list --json' "$(::: l --json)"
assert_equal 'Herdr delete dispatch failed' \
  'session delete stopped' \
  "$(::: d stopped)"
assert_equal 'tmux named session creation failed' \
  "new-session -s named -c $PWD" \
  "$(:: c named)"
assert_equal 'Herdr named session creation failed' '--session named' "$(::: c named)"
assert_equal 'tmux long create dispatch failed' \
  "new-session -s long-named -c $PWD" \
  "$(:: create long-named)"
assert_equal 'Herdr long create dispatch failed' '--session long-named' "$(::: create long-named)"

config_path="$PWD/home/files/config"
assert_equal 'tmux default-target workspace dispatch failed' \
  "new-window -c $config_path" \
  "$(:: n home/files/config)"
assert_equal 'tmux explicit-target workspace dispatch failed' \
  "new-window -t existing -c $config_path" \
  "$(:: n home/files/config existing)"

__dotfiles_herdr_new_workspace() { print -r -- "$1|${2:-default}" }
assert_equal 'Herdr workspace default target failed' \
  'home/files/config|default' \
  "$(::: n home/files/config)"
assert_equal 'Herdr workspace explicit target failed' \
  'home/files/config|stopped' \
  "$(::: n home/files/config stopped)"

:: n >/dev/null 2>&1
assert_equal 'tmux invalid usage status changed' 2 $?
ZSH

zsh -f /dev/stdin <<'ZSH_COMPLETIONS'
cd "$DOTFILES_ROOT"
path=(/usr/bin /bin)
rehash
autoload -Uz compinit
compinit -D
source home/files/zsh/20_aliases.zsh
source home/files/zsh/23_completions.zsh

[[ "${_comps[::]}" == _dotfiles_tmux_session_shortcut ]] || exit 1
[[ "${_comps[:::]}" == _dotfiles_herdr_session_shortcut ]] || exit 1
ZSH_COMPLETIONS

fish -n "$DOTFILES_ROOT/home/files/config/fish/conf.d/21_functions.fish"
fish -n "$DOTFILES_ROOT/home/files/config/fish/conf.d/23_completions.fish"
zsh -n "$DOTFILES_ROOT/home/files/zsh/20_aliases.zsh"
zsh -n "$DOTFILES_ROOT/home/files/zsh/23_completions.zsh"

printf '%s\n' 'session shortcut tests: ok'
