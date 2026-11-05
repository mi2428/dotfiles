#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
requested_host="${1:-}"
platform="$(uname -s)"

case "$platform" in
  Darwin)
    # Treat HOST=macos as "resolve the current Mac" rather than bypassing serial verification.
    if [[ -z "$requested_host" || "$requested_host" == "macos" ]]; then
      exec "$repo_root/bootstrap/detect-host.sh"
    fi

    printf '%s\n' "$requested_host"
    ;;
  Linux)
    if [[ "$requested_host" == "omarchy" ]]; then
      if [[ "$("$repo_root/bootstrap/detect-host.sh")" != omarchy ]]; then
        printf '%s\n' 'bootstrap: omarchy is not registered for this machine' >&2
        exit 1
      fi
      printf '%s\n' 'omarchy'
      exit 0
    fi

    if [[ -z "$requested_host" || "$requested_host" == "linux" ]]; then
      exec "$repo_root/bootstrap/detect-host.sh"
    fi

    printf '%s\n' "$requested_host"
    ;;
  *)
    printf '%s\n' "bootstrap: unsupported platform: $platform" >&2
    exit 1
    ;;
esac
