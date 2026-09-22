#!/bin/sh

set -eu

DOTFILES_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-gh-review-test.XXXXXX")
TEST_ROOT=$(CDPATH='' cd -- "$TEST_ROOT" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/bin" "$TEST_ROOT/github.com/owner"
git init -q --bare "$TEST_ROOT/github.com/owner/repo.git"
git init -q -b main "$TEST_ROOT/repo"
git -C "$TEST_ROOT/repo" -c user.name=Test -c user.email=test@example.com commit --allow-empty -m main -q
git -C "$TEST_ROOT/repo" remote add origin "$TEST_ROOT/github.com/owner/repo.git"
git -C "$TEST_ROOT/repo" push -q -u origin main
git -C "$TEST_ROOT/repo" switch -q -c feature
git -C "$TEST_ROOT/repo" -c user.name=Test -c user.email=test@example.com commit --allow-empty -m feature -q
git -C "$TEST_ROOT/repo" push -q -u origin feature
git -C "$TEST_ROOT/repo" switch -q main

cat >"$TEST_ROOT/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
    'repo view') printf '%s\n' owner/repo ;;
    'pr view') printf '7\tTest PR\thttps://github.com/owner/repo/pull/7\tmain\tfeature\ttester\n' ;;
    'pr checkout')
        shift 3
        test "$1" = --branch
        git fetch -q origin feature
        git checkout -q -B "$2" FETCH_HEAD
        ;;
    *) exit 1 ;;
esac
EOF
cat >"$TEST_ROOT/bin/tmux" <<'EOF'
#!/bin/sh
exit 99
EOF
cat >"$TEST_ROOT/bin/nvim" <<'EOF'
#!/bin/sh
exit 99
EOF
chmod +x "$TEST_ROOT/bin/gh" "$TEST_ROOT/bin/tmux" "$TEST_ROOT/bin/nvim"

actual=$(HOME="$TEST_ROOT/home" \
    XDG_CACHE_HOME="$TEST_ROOT/cache" \
    PATH="$TEST_ROOT/bin:$DOTFILES_ROOT/bin:$PATH" \
    DOTFILES_ROOT="$DOTFILES_ROOT" \
    TEST_REPO="$TEST_ROOT/repo" \
    fish -c 'source "$DOTFILES_ROOT/home/files/config/fish/conf.d/21_functions.fish"; gh-review --cd -C "$TEST_REPO" 7; and pwd')
expected="$TEST_ROOT/cache/gh-review/owner/repo/pr-7"

test "$actual" = "$expected"
test "$(git -C "$expected" branch --show-current)" = review/pr-7-feature

printf '%s\n' 'gh-review --cd integration: ok'
