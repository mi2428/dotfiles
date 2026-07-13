#!/bin/bash
set -e
set -o pipefail

CURDIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$CURDIR/../.." && pwd)

srcdir="$DOTFILES/home/files/config/k9s"
xdgdir="${XDG_CONFIG_HOME:-$HOME/.config}/k9s"

if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  dstdir="$xdgdir"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  dstdir="$HOME/Library/Application Support/k9s"
else
  dstdir="$xdgdir"
fi

mkdir -p "$dstdir/skins"
mkdir -p "$xdgdir/skins"
ln -snf "$srcdir/config.yaml" "$dstdir/config.yaml"
ln -snf "$srcdir/config.yaml" "$xdgdir/config.yaml"

for srcpath in "$srcdir"/skins/*.yaml; do
  filename=$(basename "$srcpath")
  ln -snf "$srcpath" "$dstdir/skins/$filename"
  ln -snf "$srcpath" "$xdgdir/skins/$filename"
done
