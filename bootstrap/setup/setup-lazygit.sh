#!/bin/bash
set -e
set -o pipefail

CURDIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$CURDIR/../.." && pwd)

srcdir="$DOTFILES/home/files/config/lazygit"

if [[ "$(uname -s)" == "Darwin" ]]; then
  dstdir="$HOME/Library/Application Support/lazygit"
else
  dstdir="${XDG_CONFIG_HOME:-$HOME/.config}/lazygit"
fi

xdgdir="${XDG_CONFIG_HOME:-$HOME/.config}/lazygit"

mkdir -p "$dstdir"
mkdir -p "$xdgdir"
ln -snf "$srcdir/config.yml" "$dstdir/config.yml"
ln -snf "$srcdir/functions.sh" "$dstdir/functions.sh"
ln -snf "$srcdir/config.yml" "$xdgdir/config.yml"
ln -snf "$srcdir/functions.sh" "$xdgdir/functions.sh"

for flavour in latte frappe macchiato mocha; do
  mkdir -p "$dstdir/themes-mergable/$flavour"
  mkdir -p "$xdgdir/themes-mergable/$flavour"
  ln -snf "$srcdir/themes-mergable/$flavour/green.yml" "$dstdir/themes-mergable/$flavour/green.yml"
  ln -snf "$srcdir/themes-mergable/$flavour/green.yml" "$xdgdir/themes-mergable/$flavour/green.yml"
done
