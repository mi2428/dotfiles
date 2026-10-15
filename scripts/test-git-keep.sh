#!/bin/sh
set -eu

DOTFILES_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-git-keep-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM
repo="$TEST_ROOT/repo"
mkdir -p "$repo/nested" "$repo/hoge"
git init -q "$repo"
git -C "$repo" config user.name Test
git -C "$repo" config user.email test@example.com
printf 'initial\n' >"$repo/nested/inside.txt"
printf 'initial\n' >"$repo/hoge/target.txt"
git -C "$repo" add .
git -C "$repo" commit -qm init
PATH="$DOTFILES_ROOT/bin:$PATH"
export PATH

printf 'changed\n' >"$repo/nested/inside.txt"
printf 'changed\n' >"$repo/hoge/target.txt"
printf 'staged\n' >"$repo/outside.txt"
git -C "$repo" add outside.txt
(cd "$repo/nested" && git keep . >/dev/null)
test "$(git -C "$repo" show --format= --name-only HEAD)" = nested/inside.txt
test "$(git -C "$repo" diff --cached --name-only)" = outside.txt
test "$(git -C "$repo" diff --name-only)" = hoge/target.txt

printf 'new\n' >"$repo/hoge/spaced name.txt"
(cd "$repo/nested" && git keep --fix ../hoge >/dev/null)
test "$(git -C "$repo" show --format= --name-only HEAD)" = "$(printf 'hoge/spaced name.txt\nhoge/target.txt')"
case "$(git -C "$repo" log -1 --format=%s)" in
    'bugfix: '*) ;;
    *) printf '%s\n' 'git keep --fix lost its message prefix' >&2; exit 1 ;;
esac
test "$(git -C "$repo" diff --cached --name-only)" = outside.txt

before=$(git -C "$repo" rev-parse HEAD)
if (cd "$repo/nested" && git keep ../missing) >/dev/null 2>&1; then
    printf '%s\n' 'git keep accepted a missing path' >&2
    exit 1
fi
test "$(git -C "$repo" rev-parse HEAD)" = "$before"
test "$(git -C "$repo" diff --cached --name-only)" = outside.txt

(cd "$repo/nested" && git keep >/dev/null)
test "$(git -C "$repo" show --format= --name-only HEAD)" = outside.txt
test -z "$(git -C "$repo" status --porcelain)"
printf '%s\n' 'git keep path-scoped commits: ok'
