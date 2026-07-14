#!/usr/bin/env bash
set -euo pipefail

case "$(uname -s)" in
  Darwin)
    scutil --get ComputerName 2>/dev/null || hostname -s
    ;;
  Linux)
    hostname -s
    ;;
  *)
    printf '%s\n' "bootstrap: unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac
