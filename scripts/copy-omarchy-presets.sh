#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $(uname -s) != Linux || $("$repo_root/bootstrap/detect-host.sh") != omarchy ]]; then
  echo 'omarchy.copy requires the registered Omarchy machine' >&2
  exit 1
fi

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
presets=(
  hypr/input.lua:hypr/omarchy/input.lua
  hypr/bindings.lua:hypr/omarchy/bindings.lua
  hypr/monitors.lua:hypr/omarchy/monitors.lua
  hypr/looknfeel.lua:hypr/omarchy/looknfeel.lua
  ghostty/config:ghostty/config.ghostty
)

# Validate every path before changing anything. A missing preset, directory,
# or dangling target link is an error, not a reason to partially reset a desktop.
for preset in "${presets[@]}"; do
  source_file="$repo_root/home/files/config/${preset#*:}"
  if [[ ! -f $source_file ]]; then
    printf 'Missing preset: %s\n' "$source_file" >&2
    exit 1
  fi
  target="$config_home/${preset%%:*}"
  if [[ (-e $target || -L $target) && ! -f $target ]]; then
    printf 'Not a regular file: %s\n' "$target" >&2
    exit 1
  fi
done

for preset in "${presets[@]}"; do
  target="$config_home/${preset%%:*}"
  mkdir -p "$(dirname -- "$target")"
  temporary=$(mktemp "$target.XXXXXX")
  trap 'rm -f -- "$temporary"' EXIT
  install -m 0644 "$repo_root/home/files/config/${preset#*:}" "$temporary"
  if [[ -e $target ]]; then
    backup=$(mktemp "$target.before-dotfiles.XXXXXX")
    cp -L -- "$target" "$backup"
    printf 'Backup: %s\n' "$backup"
  fi
  mv -fT -- "$temporary" "$target"
  printf 'Copied: %s\n' "$target"
done
