#!/usr/bin/env bash
set -euo pipefail

os="$(uname -s)"
arch="$(uname -m)"

case "$os:$arch" in
  Darwin:arm64|Darwin:aarch64)
    printf '%s\n' 'aarch64-darwin'
    ;;
  Darwin:x86_64)
    printf '%s\n' 'x86_64-darwin'
    ;;
  Linux:arm64|Linux:aarch64)
    printf '%s\n' 'aarch64-linux'
    ;;
  Linux:x86_64|Linux:amd64)
    printf '%s\n' 'x86_64-linux'
    ;;
  *)
    printf '%s\n' "bootstrap: unsupported platform for nix system detection: $os/$arch" >&2
    exit 1
    ;;
esac
