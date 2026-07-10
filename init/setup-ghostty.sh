#!/bin/bash
set -e
set -o pipefail

CURDIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$CURDIR/.." && pwd)

src="$DOTFILES/etc/ghostty/config.ghostty"
dstdir="$HOME/Library/Application Support/com.mitchellh.ghostty"
dst="$dstdir/config.ghostty"

mkdir -p "$dstdir"
ln -snf "$src" "$dst"
