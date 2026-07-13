#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${DOTFILES_BOOTSTRAP_CHEZMOI_BIN:-}" ]]; then
  printf '%s\n' "$DOTFILES_BOOTSTRAP_CHEZMOI_BIN"
  exit 0
fi

if command -v chezmoi >/dev/null 2>&1; then
  command -v chezmoi
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' 'bootstrap: curl is required to install chezmoi' >&2
  exit 1
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/bootstrap/bin"
chezmoi_bin="$cache_dir/chezmoi"

if [[ ! -x "$chezmoi_bin" ]]; then
  mkdir -p "$cache_dir"
  curl -fsLS get.chezmoi.io | sh -s -- -b "$cache_dir" >/dev/null
fi

printf '%s\n' "$chezmoi_bin"
