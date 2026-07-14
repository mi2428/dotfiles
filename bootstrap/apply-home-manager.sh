#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap/apply-home-manager.sh --host HOST
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

if [[ "$(uname -s)" != "Linux" ]]; then
  printf '%s\n' "bootstrap: Linux host '$host' requires Linux" >&2
  exit 1
fi

host="$("$repo_root/bootstrap/resolve-host.sh" "$host")"

case "$host" in
  linux|docker) ;;
  *)
    printf '%s\n' "bootstrap: unsupported Linux host: $host" >&2
    exit 1
    ;;
esac

runtime_user="$(id -un)"
runtime_home="${HOME:?bootstrap: HOME must be set}"

mkdir -p "$runtime_home"

nix_bin="$("$repo_root/bootstrap/install-nix.sh")"
nix_bin_dir="$(dirname "$nix_bin")"
cache_dir="${XDG_CACHE_HOME:-$runtime_home/.cache}/dotfiles/bootstrap"
activation_link="$cache_dir/home-manager-${host}"

mkdir -p "$cache_dir"

PATH="$nix_bin_dir:$PATH" \
DOTFILES_RUNTIME_USER="$runtime_user" \
DOTFILES_RUNTIME_HOME="$runtime_home" \
  "$nix_bin" build \
    --impure \
    --extra-experimental-features 'nix-command flakes' \
    "path:${repo_root}#homeConfigurations.${host}.activationPackage" \
    --out-link "$activation_link"

HOME="$runtime_home" \
USER="$runtime_user" \
PATH="$nix_bin_dir:$PATH" \
  "$activation_link/activate"
