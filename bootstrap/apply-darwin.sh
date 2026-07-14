#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap/apply-darwin.sh --host HOST
EOF
}

host=""

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

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' "bootstrap: darwin host '$host' requires macOS" >&2
  exit 1
fi

host="$("$repo_root/bootstrap/resolve-host.sh" "$host")"

if [[ "$host" != "macos" ]]; then
  printf '%s\n' "bootstrap: unsupported darwin host: $host" >&2
  exit 1
fi

runtime_user="$(id -un)"
runtime_home="${HOME:?bootstrap: HOME must be set}"

nix_bin="$("$repo_root/bootstrap/install-nix.sh")"
nix_bin_dir="$(dirname "$nix_bin")"
cache_dir="${XDG_CACHE_HOME:-$runtime_home/.cache}/dotfiles/bootstrap"
system_link="$cache_dir/darwin-${host}"
nix_config='experimental-features = nix-command flakes'

mkdir -p "$cache_dir"

PATH="$nix_bin_dir:$PATH" \
NIX_CONFIG="$nix_config" \
  "$nix_bin" build \
    "path:${repo_root}#darwinConfigurations.${host}.system" \
    --out-link "$system_link"

sudo env \
  HOME="$runtime_home" \
  USER="$runtime_user" \
  PATH="$nix_bin_dir:$PATH" \
  NIX_CONFIG="$nix_config" \
  "$system_link/sw/bin/darwin-rebuild" switch --flake "path:${repo_root}#${host}"
