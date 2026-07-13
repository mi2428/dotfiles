#!/bin/bash
set -e
set -o pipefail

CURDIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$CURDIR/../.." && pwd)

src="$DOTFILES/home/files/config/ghostty/config.ghostty"
dstdir="$HOME/Library/Application Support/com.mitchellh.ghostty"
dst="$dstdir/config.ghostty"
themes_src="$DOTFILES/home/files/config/ghostty/themes"
themes_dst="$dstdir/themes"
xdg_dir="$HOME/.config/ghostty"
xdg_config="$xdg_dir/config"
xdg_config_ghostty="$xdg_dir/config.ghostty"
xdg_themes="$xdg_dir/themes"

mkdir -p "$dstdir"
mkdir -p "$xdg_dir"
ln -snf "$src" "$dst"
ln -snf "$themes_src" "$themes_dst"
ln -snf "$src" "$xdg_config"
ln -snf "$src" "$xdg_config_ghostty"
ln -snf "$themes_src" "$xdg_themes"
