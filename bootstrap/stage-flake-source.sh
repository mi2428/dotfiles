#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_home="${HOME:?bootstrap: HOME must be set}"
cache_dir="${XDG_CACHE_HOME:-$runtime_home/.cache}/dotfiles/bootstrap"
mkdir -p "$cache_dir"
stage_dir="$(mktemp -d "$cache_dir/flake-source.XXXXXX")"

(
  cd "$repo_root"
  find . \
    -path './.git' -prune -o \
    \( -type d -o -type f -o -type l \) -print0 |
    tar --null --files-from=- --create --file - --no-recursion
) | (
  cd "$stage_dir"
  tar --extract --file -
)

printf '%s\n' "$stage_dir"
