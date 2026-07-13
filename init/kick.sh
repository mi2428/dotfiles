#!/usr/bin/env bash
set -euo pipefail

cd "$HOME" || exit 1

DIST=""
SUDO=()

if [[ -f /etc/lsb-release ]]; then
  DIST="$(grep '^DISTRIB_ID=' /etc/lsb-release | cut -d '=' -f 2)"
fi

if [[ "$(id -u)" != "0" ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "kick.sh: sudo is required when not running as root." >&2
    exit 1
  fi
  SUDO=(sudo)
fi

case "$DIST" in
  Ubuntu)
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" DEBIAN_FRONTEND=noninteractive \
      apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        make \
        sudo \
        xz-utils
    ;;
  *)
    exit 127 ;;
esac

if [[ ! -d "$HOME/dotfiles/.git" ]]; then
  git clone --depth 1 https://github.com/mi2428/dotfiles "$HOME/dotfiles"
fi

cd "$HOME/dotfiles" || exit 1

case "$DIST" in
  Ubuntu)
    make bootstrap ;;
esac
