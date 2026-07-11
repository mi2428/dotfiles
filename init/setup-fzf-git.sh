#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/junegunn/fzf-git.sh.git"
REPO_REV="fdf632c53262dfcc44fc09d591e462e9f8fcae83"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fzf-git"

mkdir -p "$(dirname "$INSTALL_DIR")"

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  rm -rf "$INSTALL_DIR"
  git init "$INSTALL_DIR" >/dev/null
  git -C "$INSTALL_DIR" remote add origin "$REPO_URL"
fi

current_rev="$(git -C "$INSTALL_DIR" rev-parse HEAD 2>/dev/null || true)"
if [[ "$current_rev" != "$REPO_REV" ]]; then
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$REPO_REV" >/dev/null
  git -C "$INSTALL_DIR" checkout --force FETCH_HEAD >/dev/null
fi
