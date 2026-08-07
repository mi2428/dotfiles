#!/bin/sh

set -eu

DOTFILES_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-work-test.XXXXXX")
TEST_ROOT=$(CDPATH='' cd -- "$TEST_ROOT" && pwd -P)
TMUX_ROOT=$(mktemp -d "/tmp/dotfiles-work-tmux.XXXXXX")
TMUX_ROOT=$(CDPATH='' cd -- "$TMUX_ROOT" && pwd -P)

run_tmux() {
    env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$TMUX_ROOT" tmux "$@"
}

cleanup() {
    run_tmux kill-server >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$TEST_ROOT" "$TMUX_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/repo" "$TEST_ROOT/outside"
chmod 700 "$TMUX_ROOT"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" -c user.name=Test -c user.email=test@example.com commit --allow-empty -m init -q

env -u TMUX -u TMUX_PANE -u WORK_WORKTREE_HOME \
    HOME="$TEST_ROOT/home" \
    SHELL=/bin/bash \
    TMUX_TMPDIR="$TMUX_ROOT" \
    WORK_NO_ATTACH=1 \
    "$DOTFILES_ROOT/bin/work" -w -c feature/test -C "$TEST_ROOT/repo"

worktree=$(git -C "$TEST_ROOT/repo" for-each-ref --format='%(worktreepath)' refs/heads/feature/test)
case "$worktree" in
    "$TEST_ROOT/home/io/worktrees/"*/feature-test) ;;
    *) printf 'unexpected worktree path: %s\n' "$worktree" >&2; exit 1 ;;
esac
test "$(git -C "$worktree" branch --show-current)" = feature/test
test "$(run_tmux list-windows -a -F '#{window_id}' | wc -l | tr -d ' ')" = 1
preview=$(env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$TMUX_ROOT" "$DOTFILES_ROOT/bin/work" --preview-worktree "$worktree")
test -n "$preview"
case "$preview" in
    branch:*) printf '%s\n' 'worktree preview did not capture the tmux window' >&2; exit 1 ;;
esac

cd "$TEST_ROOT/outside"
env -u TMUX -u TMUX_PANE -u WORK_WORKTREE_HOME \
    HOME="$TEST_ROOT/home" \
    SHELL=/bin/bash \
    TMUX_TMPDIR="$TMUX_ROOT" \
    WORK_NO_ATTACH=1 \
    FZF_DEFAULT_OPTS='--filter=feature/test --select-1 --exit-0' \
    "$DOTFILES_ROOT/bin/work" -l

test "$(run_tmux list-windows -a -F '#{window_id}' | wc -l | tr -d ' ')" = 1
test "$(run_tmux list-panes -a -F '#{pane_current_path}')" = "$worktree"

printf '%s\n' 'work integration: ok'
