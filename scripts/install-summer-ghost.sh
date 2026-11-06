#!/usr/bin/env bash
set -euo pipefail

# Upstream pins font inputs and Python packages; pin its builder here as well.
revision=622be738651660cf1851c619c92bd813d97c6dbd
source_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/font-summer-ghost/$revision"
platform=$(uname -s)
set -- git make uv
case "$platform" in
  Linux)
    font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/SummerGhost"
    set -- "$@" fc-cache
    ;;
  Darwin) font_dir="$HOME/Library/Fonts/SummerGhost" ;;
  *)
    printf '%s\n' 'Unsupported font installation platform' >&2
    exit 1
    ;;
esac

for tool; do
  if ! command -v "$tool" >/dev/null; then
    printf 'Missing build tool: %s\n' "$tool" >&2
    exit 1
  fi
done
if [ ! -d "$source_dir" ]; then
  mkdir -p "$(dirname "$source_dir")"
  git clone --no-checkout https://github.com/mi2428/font-summer-ghost.git "$source_dir"
  git -C "$source_dir" checkout --detach "$revision"
fi
builder_revision=$(git -C "$source_dir" rev-parse HEAD)
if [ "$builder_revision" != "$revision" ]; then
  printf 'Unexpected builder revision: %s\n' "$source_dir" >&2
  exit 1
fi
builder_status=$(git -C "$source_dir" status --porcelain)
if [ -n "$builder_status" ]; then
  printf 'Builder has local changes: %s\n' "$source_dir" >&2
  exit 1
fi

# Upstream check already builds and validates all four styles.
make -C "$source_dir" check
make -C "$source_dir" install "FONTDIR=$font_dir"
if [ "$platform" = Linux ]; then
  fc-cache -f "$font_dir"
fi
printf 'Summer Ghost %s installed in %s\n' "$revision" "$font_dir"
