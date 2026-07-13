#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap/apply-darwin.sh --host HOST [--home PATH] [--user USER]
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

case "$host" in
  macos)
    expected_home="/Users/teo"
    expected_user="teo"
    ;;
  *)
    printf '%s\n' "bootstrap: unsupported darwin host: $host" >&2
    exit 1
    ;;
esac

if [[ "$target_home" != "$expected_home" ]]; then
  printf '%s\n' "bootstrap: pure flake host '$host' requires home '$expected_home' (got '$target_home')" >&2
  exit 1
fi

if [[ "$target_user" != "$expected_user" ]]; then
  printf '%s\n' "bootstrap: pure flake host '$host' requires user '$expected_user' (got '$target_user')" >&2
  exit 1
fi

nix_bin="$("$repo_root/bootstrap/install-nix.sh")"
nix_bin_dir="$(dirname "$nix_bin")"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/bootstrap"
system_link="$cache_dir/darwin-${host}"
nix_config='experimental-features = nix-command flakes'

mkdir -p "$cache_dir"

PATH="$nix_bin_dir:$PATH" \
NIX_CONFIG="$nix_config" \
  "$nix_bin" build \
    "path:${repo_root}#darwinConfigurations.${host}.system" \
    --out-link "$system_link"

sudo env \
  HOME="$target_home" \
  USER="$target_user" \
  PATH="$nix_bin_dir:$PATH" \
  NIX_CONFIG="$nix_config" \
  "$system_link/sw/bin/darwin-rebuild" switch --flake "path:${repo_root}#${host}"
