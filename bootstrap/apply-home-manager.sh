#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap/apply-home-manager.sh --host HOST
EOF
}

host_home() {
  case "$1" in
    linux-server|docker-dev)
      printf '%s\n' '/home/teo'
      ;;
    *)
      printf '%s\n' "bootstrap: unsupported linux host: $1" >&2
      return 1
      ;;
  esac
}

host_user() {
  case "$1" in
    linux-server|docker-dev)
      printf '%s\n' 'teo'
      ;;
    *)
      printf '%s\n' "bootstrap: unsupported linux host: $1" >&2
      return 1
      ;;
  esac
}

host=""

while (($# > 0)); do
  case "$1" in
    --host)
      host="$2"
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

target_home="$(host_home "$host")"
target_user="$(host_user "$host")"

mkdir -p "$target_home"

nix_bin="$("$repo_root/bootstrap/install-nix.sh")"
nix_bin_dir="$(dirname "$nix_bin")"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/bootstrap"
activation_link="$cache_dir/home-manager-${host}"

mkdir -p "$cache_dir"

PATH="$nix_bin_dir:$PATH" \
  "$nix_bin" build \
    --extra-experimental-features 'nix-command flakes' \
    "path:${repo_root}#homeConfigurations.${host}.activationPackage" \
    --out-link "$activation_link"

HOME="$target_home" \
USER="$target_user" \
PATH="$nix_bin_dir:$PATH" \
  "$activation_link/activate"
