#!/bin/bash
set -e
set -o pipefail

CURDIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES=$(cd "$CURDIR/.." && pwd)

srcdir="$DOTFILES/etc/vscode"
src="$srcdir/settings.json"
extensions="$srcdir/extensions.txt"

macos_dir="$HOME/Library/Application Support/Code/User"
xdg_dir="$HOME/.config/Code/User"

mkdir -p "$macos_dir"
mkdir -p "$xdg_dir"
ln -snf "$src" "$macos_dir/settings.json"
ln -snf "$src" "$xdg_dir/settings.json"

if ! command -v code >/dev/null 2>&1; then
  exit 0
fi

while IFS= read -r extension; do
  if [[ -z "$extension" ]]; then
    continue
  fi
  code --install-extension "$extension" --force
done < "$extensions"
