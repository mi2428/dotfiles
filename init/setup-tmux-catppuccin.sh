#!/bin/bash
set -e
set -o pipefail

plugin_dir="$HOME/.config/tmux/plugins/catppuccin/tmux"
plugin_repo="https://github.com/catppuccin/tmux.git"
plugin_ref="v2.3.0"

mkdir -p "$(dirname "$plugin_dir")"

if [[ -d "$plugin_dir/.git" ]]; then
  git -C "$plugin_dir" fetch --tags --force origin
else
  rm -rf "$plugin_dir"
  git clone "$plugin_repo" "$plugin_dir"
fi

git -C "$plugin_dir" checkout --force "$plugin_ref"
