#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-dev-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

(
    CDPATH='' cd -- "$scratch"
    HOME=$scratch DOTFILES_REAL_HOME=$scratch "$root/bin/dotfiles-dev" --help >/dev/null
    actual=$(HOME=$scratch DOTFILES_REAL_HOME=$scratch "$root/bin/git.dev" config --get include.path)
    [ "$actual" = "$root/home/files/git/catppuccin-delta.gitconfig" ]
)

mkdir -p "$scratch/.local/bin" "$scratch/.local/scripts"
ln -s "$root/bin/dotfiles-dev" "$scratch/.local/bin/dotfiles-dev"
ln -s "$root/bin/git.dev" "$scratch/.local/bin/git.dev"
ln -s "$root/scripts/dotfiles-dev.sh" "$scratch/.local/scripts/dotfiles-dev.sh"
(
    CDPATH='' cd -- "$root"
    HOME=$scratch DOTFILES_REAL_HOME=$scratch "$scratch/.local/bin/dotfiles-dev" --help >/dev/null
    actual=$(HOME=$scratch DOTFILES_REAL_HOME=$scratch "$scratch/.local/bin/git.dev" config --get include.path)
    [ "$actual" = "$root/home/files/git/catppuccin-delta.gitconfig" ]
)

for wrapper in "$root"/bin/*.dev; do
    grep -Fq "exec \"\$script_dir/../scripts/dotfiles-dev.sh\"" "$wrapper"
done

printf '%s\n' 'Dev wrappers and public entrypoint: ok'
