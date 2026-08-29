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
export DOTFILES_RUNTIME_USER="$runtime_user"
export DOTFILES_RUNTIME_HOME="$runtime_home"
stage_repo="$("$repo_root/bootstrap/stage-flake-source.sh")"

nix_bin="$("$repo_root/bootstrap/install-nix.sh")"
nix_bin_dir="$(dirname "$nix_bin")"
cache_dir="${XDG_CACHE_HOME:-$runtime_home/.cache}/dotfiles/bootstrap"
system_link="$cache_dir/darwin-${host}"
system_only_link="$cache_dir/darwin-system-only-${host}"
home_link="$cache_dir/home-manager-${host}"
system_only_state="$cache_dir/darwin-system-only-${host}.applied"
nix_config='experimental-features = nix-command flakes'

mkdir -p "$cache_dir"

trap 'rm -rf "$stage_repo"' EXIT

PATH="$nix_bin_dir:$PATH" \
NIX_CONFIG="$nix_config" \
  "$nix_bin" build \
    --impure \
    "path:${stage_repo}#packages.aarch64-darwin.${host}-system" \
    --out-link "$system_only_link"

PATH="$nix_bin_dir:$PATH" \
NIX_CONFIG="$nix_config" \
  "$nix_bin" build \
    --impure \
    "path:${stage_repo}#homeConfigurations.${host}.activationPackage" \
    --out-link "$home_link"

desired_system_only_path="$(readlink "$system_only_link")"
applied_system_only_path=""
if [[ -f "$system_only_state" ]]; then
  applied_system_only_path="$(<"$system_only_state")"
fi

if [[ -n "$applied_system_only_path" && "$applied_system_only_path" == "$desired_system_only_path" ]]; then
  HOME="$runtime_home" \
  USER="$runtime_user" \
  PATH="$nix_bin_dir:$PATH" \
    "$home_link/activate"
  exit 0
fi

PATH="$nix_bin_dir:$PATH" \
NIX_CONFIG="$nix_config" \
  "$nix_bin" build \
    --impure \
    "path:${stage_repo}#darwinConfigurations.${host}.system" \
    --out-link "$system_link"

sudo env \
  HOME="$runtime_home" \
  USER="$runtime_user" \
  DOTFILES_RUNTIME_USER="$runtime_user" \
  DOTFILES_RUNTIME_HOME="$runtime_home" \
  PATH="$nix_bin_dir:$PATH" \
  NIX_CONFIG="$nix_config" \
  "$system_link/sw/bin/darwin-rebuild" switch --impure --flake "path:${stage_repo}#${host}"

printf '%s\n' "$desired_system_only_path" > "$system_only_state"
