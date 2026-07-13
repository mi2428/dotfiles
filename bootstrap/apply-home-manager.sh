#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap/apply-home-manager.sh --host HOST [--home PATH] [--user USER]
EOF
}

host=""
target_home="${DOTFILES_HOME:-$HOME}"
target_user="${DOTFILES_USER:-${USER:-teo}}"

while (($# > 0)); do
  case "$1" in
    --host)
      host="$2"
      shift 2
      ;;
    --home)
      target_home="$2"
      shift 2
      ;;
    --user)
      target_user="$2"
      shift 2
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
  printf '%s\n' 'bootstrap: --host is required' >&2
  exit 1
fi

mkdir -p "$target_home"

nix_bin="$("$repo_root/bootstrap/install-nix.sh")"
nix_system="${DOTFILES_NIX_SYSTEM:-$("$repo_root/bootstrap/detect-nix-system.sh")}"
nix_bin_dir="$(dirname "$nix_bin")"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/bootstrap"
activation_link="$cache_dir/home-manager-${host}"

mkdir -p "$cache_dir"

DOTFILES_HOME="$target_home" \
DOTFILES_USER="$target_user" \
DOTFILES_NIX_SYSTEM="$nix_system" \
  "$nix_bin" build \
    --impure \
    --extra-experimental-features 'nix-command flakes' \
    "path:${repo_root}#homeConfigurations.${host}.activationPackage" \
    --out-link "$activation_link"

HOME="$target_home" \
USER="$target_user" \
PATH="$nix_bin_dir:$PATH" \
  "$activation_link/activate"
