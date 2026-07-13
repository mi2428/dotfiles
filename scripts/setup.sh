#!/usr/bin/env bash
set -euo pipefail

repo_url="${DOTFILES_REPO_URL:-https://github.com/mi2428/dotfiles.git}"
repo_branch="${DOTFILES_REPO_BRANCH:-master}"
target_dir="${DOTFILES_TARGET_DIR:-$HOME/dotfiles}"

log() {
  printf '%s\n' "setup: $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "setup: missing required command: $1" >&2
    exit 1
  fi
}

require_cmd git

if [ -e "$target_dir/.git" ]; then
  if ! git -C "$target_dir" diff --quiet || ! git -C "$target_dir" diff --cached --quiet; then
    printf '%s\n' "setup: refusing to update dirty repository at $target_dir" >&2
    exit 1
  fi
  log "updating existing repository at $target_dir"
  git -C "$target_dir" fetch --depth 1 origin "$repo_branch"
  git -C "$target_dir" switch "$repo_branch"
  git -C "$target_dir" pull --ff-only origin "$repo_branch"
elif [ -e "$target_dir" ]; then
  printf '%s\n' "setup: target exists but is not a git repository: $target_dir" >&2
  exit 1
else
  log "cloning $repo_url#$repo_branch into $target_dir"
  git clone --depth 1 --branch "$repo_branch" "$repo_url" "$target_dir"
fi

log "running bootstrap/bootstrap.sh"
exec "$target_dir/bootstrap/bootstrap.sh" "$@"
