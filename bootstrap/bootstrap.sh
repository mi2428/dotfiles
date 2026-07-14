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
  "$repo_root/bootstrap/resolve-host.sh" "${1:-}"
}

host="${DOTFILES_BOOTSTRAP_HOST:-}"
skip_home_manager="${DOTFILES_BOOTSTRAP_SKIP_HOME_MANAGER:-0}"
skip_nix_install="${DOTFILES_BOOTSTRAP_SKIP_NIX_INSTALL:-0}"

while (($# > 0)); do
  case "$1" in
    --host)
      if (($# < 2)); then
        printf '%s\n' 'bootstrap: --host requires a value' >&2
        exit 1
      fi
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

host="$(detect_host "$host")"

runtime_user="$(id -un)"
runtime_home="${HOME:?bootstrap: HOME must be set}"

case "$(uname -s):$host" in
  Darwin:macos|Linux:linux|Linux:docker) ;;
  Darwin:*)
    printf '%s\n' "bootstrap: unsupported macOS host: $host" >&2
    exit 1
    ;;
  Linux:*)
    printf '%s\n' "bootstrap: unsupported Linux host: $host" >&2
    exit 1
    ;;
  *)
    printf '%s\n' "bootstrap: unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac

mkdir -p "$runtime_home" "$runtime_home/.config"

chezmoi_bin="$("$repo_root/bootstrap/install-chezmoi.sh")"

log "applying chezmoi source state to $runtime_home"
HOME="$runtime_home" USER="$runtime_user" \
"$chezmoi_bin" apply \
  --force \
  --init \
  --no-tty \
  --source "$repo_root/chezmoi" \
  --destination "$runtime_home"

if [[ "$skip_home_manager" == "1" ]]; then
  log 'skipping Nix activation'
  exit 0
fi

log "applying Nix activation for host '$host'"
case "$host" in
  macos)
    DOTFILES_BOOTSTRAP_SKIP_NIX_INSTALL="$skip_nix_install" \
      "$repo_root/bootstrap/apply-darwin.sh" --host "$host"
    ;;
  linux|docker)
    DOTFILES_BOOTSTRAP_SKIP_NIX_INSTALL="$skip_nix_install" \
      "$repo_root/bootstrap/apply-home-manager.sh" --host "$host"
    ;;
esac
