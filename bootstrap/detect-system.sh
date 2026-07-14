#!/usr/bin/env bash
set -euo pipefail

platform="$(uname -s)"
arch="$(uname -m)"

case "${platform}:${arch}" in
  Linux:aarch64|Linux:arm64)
    printf '%s\n' 'aarch64-linux'
    ;;
  Linux:x86_64|Linux:amd64)
    printf '%s\n' 'x86_64-linux'
    ;;
  Darwin:aarch64|Darwin:arm64)
    printf '%s\n' 'aarch64-darwin'
    ;;
  Darwin:x86_64|Darwin:amd64)
    printf '%s\n' 'x86_64-darwin'
    ;;
  *)
    printf '%s\n' "bootstrap: unsupported platform/architecture: ${platform}/${arch}" >&2
    exit 1
    ;;
esac
