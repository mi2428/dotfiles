#!/usr/bin/env bash
set -euo pipefail

resolve_existing_nix() {
  if [[ -n "${DOTFILES_BOOTSTRAP_NIX_BIN:-}" ]]; then
    printf '%s\n' "$DOTFILES_BOOTSTRAP_NIX_BIN"
    return 0
  fi

  if command -v nix >/dev/null 2>&1; then
    command -v nix
    return 0
  fi

  for candidate in \
    "$HOME/.nix-profile/bin/nix" \
    "$HOME/.local/state/nix/profile/bin/nix" \
    "/nix/var/nix/profiles/default/bin/nix"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

platform="$(uname -s)"
case "$platform" in
  Darwin|Linux) ;;
  *)
    printf '%s\n' "bootstrap: unsupported platform for Nix installation: $platform" >&2
    exit 1
    ;;
esac

prepare_linux_store() {
  if [[ -d /nix ]]; then
    return 0
  fi

  if [[ "$(id -u)" == "0" ]]; then
    mkdir -m 0755 /nix
    chown "$(id -un)" /nix
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    printf '%s\n' 'bootstrap: sudo is required to create /nix for a single-user Linux install' >&2
    exit 1
  fi

  sudo mkdir -m 0755 /nix
  sudo chown "$(id -un)" /nix
}

download_nix_installer() {
  local destination="$1"
  local installer_url="${DOTFILES_BOOTSTRAP_NIX_INSTALLER_URL:-https://nixos.org/nix/install}"

  if curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 5 \
    --retry-delay 2 \
    --retry-all-errors \
    "$installer_url" \
    -o "$destination"; then
    return 0
  fi

  printf '%s\n' "bootstrap: failed to download the Nix installer from $installer_url" >&2
  return 1
}

if nix_bin="$(resolve_existing_nix)"; then
  printf '%s\n' "$nix_bin"
  exit 0
fi

if [[ "${DOTFILES_BOOTSTRAP_SKIP_NIX_INSTALL:-0}" == "1" ]]; then
  printf '%s\n' 'bootstrap: nix is required but installation is disabled' >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' 'bootstrap: curl is required to install nix' >&2
  exit 1
fi

installer="$(mktemp "${TMPDIR:-/tmp}/nix-install.XXXXXX.sh")"
trap 'rm -f "$installer"' EXIT

download_nix_installer "$installer"
installer_args=(--yes --no-modify-profile)

if [[ -n "${DOTFILES_BOOTSTRAP_NIX_EXTRA_CONF_FILE:-}" ]]; then
  installer_args+=(--nix-extra-conf-file "$DOTFILES_BOOTSTRAP_NIX_EXTRA_CONF_FILE")
fi

case "$platform" in
  Darwin)
    if [[ "${DOTFILES_BOOTSTRAP_DARWIN_DAEMON_INSTALL:-0}" != "1" ]]; then
      printf '%s\n' \
        'bootstrap: macOS needs an existing nix install or DOTFILES_BOOTSTRAP_DARWIN_DAEMON_INSTALL=1 for a daemon install' >&2
      exit 1
    fi
    sh "$installer" --daemon "${installer_args[@]}" >&2
    ;;
  Linux)
    prepare_linux_store
    sh "$installer" --no-daemon "${installer_args[@]}" >&2
    ;;
  *)
    printf '%s\n' "bootstrap: unsupported platform for Nix installation: $platform" >&2
    exit 1
    ;;
esac

if ! nix_bin="$(resolve_existing_nix)"; then
  printf '%s\n' 'bootstrap: nix installation completed but no nix binary was found' >&2
  exit 1
fi

printf '%s\n' "$nix_bin"
