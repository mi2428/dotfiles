#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap/bootstrap.sh [--host HOST] [--skip-home-manager]
                              [--skip-nix-install]

Bootstraps chezmoi-managed files and then applies the Nix activation for the
selected host.

Environment:
  DOTFILES_BOOTSTRAP_HOST            Default host selection
  DOTFILES_BOOTSTRAP_SKIP_HOME_MANAGER=1
  DOTFILES_BOOTSTRAP_SKIP_NIX_INSTALL=1
  DOTFILES_BOOTSTRAP_DARWIN_DAEMON_INSTALL=1
  DOTFILES_BOOTSTRAP_CHEZMOI_BIN     Path to a preinstalled chezmoi binary
  DOTFILES_BOOTSTRAP_NIX_BIN         Path to a preinstalled nix binary
EOF
}

log() {
  printf '%s\n' "bootstrap: $*"
}

detect_host() {
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' 'macos'
      ;;
    Linux)
      printf '%s\n' 'linux-server'
      ;;
    *)
      printf '%s\n' "bootstrap: unsupported platform: $(uname -s)" >&2
      return 1
      ;;
  esac
}

host_home() {
  case "$1" in
    macos)
      printf '%s\n' '/Users/teo'
      ;;
    linux-server|docker-dev)
      printf '%s\n' '/home/teo'
      ;;
    *)
      printf '%s\n' "bootstrap: unsupported host: $1" >&2
      return 1
      ;;
  esac
}

host_user() {
  case "$1" in
    macos|linux-server|docker-dev)
      printf '%s\n' 'teo'
      ;;
    *)
      printf '%s\n' "bootstrap: unsupported host: $1" >&2
      return 1
      ;;
  esac
}

host="${DOTFILES_BOOTSTRAP_HOST:-}"
skip_home_manager="${DOTFILES_BOOTSTRAP_SKIP_HOME_MANAGER:-0}"
skip_nix_install="${DOTFILES_BOOTSTRAP_SKIP_NIX_INSTALL:-0}"

while (($# > 0)); do
  case "$1" in
    --host)
      host="$2"
      shift 2
      ;;
    --skip-home-manager)
      skip_home_manager=1
      shift
      ;;
    --skip-nix-install)
      skip_nix_install=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '%s\n' "bootstrap: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$host" ]]; then
  host="$(detect_host)"
fi

target_home="$(host_home "$host")"
target_user="$(host_user "$host")"

mkdir -p "$target_home" "$target_home/.config"

chezmoi_bin="$("$repo_root/bootstrap/install-chezmoi.sh")"
chezmoi_apply_flags=()

if [[ "$host" != "macos" ]]; then
  chezmoi_apply_flags+=(--include symlinks)
fi

log "applying chezmoi source state to $target_home"
DOTFILES_REPO_ROOT="$repo_root" \
  "$chezmoi_bin" apply \
    --force \
    --no-tty \
    "${chezmoi_apply_flags[@]}" \
    --source "$repo_root/chezmoi" \
    --destination "$target_home"

if [[ "$skip_home_manager" == "1" ]]; then
  log 'skipping Nix activation'
  exit 0
fi

log "applying Nix activation for host '$host'"
if [[ "$host" == "macos" ]]; then
  DOTFILES_BOOTSTRAP_SKIP_NIX_INSTALL="$skip_nix_install" \
    "$repo_root/bootstrap/apply-darwin.sh" --host "$host"
else
  DOTFILES_BOOTSTRAP_SKIP_NIX_INSTALL="$skip_nix_install" \
    "$repo_root/bootstrap/apply-home-manager.sh" --host "$host"
fi
