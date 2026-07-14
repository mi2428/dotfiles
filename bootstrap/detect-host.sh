#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bootstrap/host-map.sh
source "$repo_root/bootstrap/host-map.sh"

detect_macos_host() {
  serial=""

  if command -v ioreg >/dev/null 2>&1; then
    serial="$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F '"' '/IOPlatformSerialNumber/ { print $4 }')"
  fi

  if [[ -z "$serial" ]] && command -v system_profiler >/dev/null 2>&1; then
    serial="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F ': ' '/Serial Number/ { print $2; exit }')"
  fi

  # Map hardware identity to a stable flake host key so local machine naming does not matter.
  if [[ -n "$serial" ]] && map_macos_serial_to_host "$serial"; then
    return 0
  fi

  printf '%s\n' 'macos'
}

detect_linux_host() {
  machine_id=""

  if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    printf '%s\n' 'docker'
    return 0
  fi

  if [[ -r /proc/1/cgroup ]] && grep -Eq '(docker|containerd|podman|lxc)' /proc/1/cgroup; then
    printf '%s\n' 'docker'
    return 0
  fi

  if [[ -r /etc/machine-id ]]; then
    machine_id="$(tr -d '\n' < /etc/machine-id)"
  fi

  # Fall back to the base Linux config when the machine identity is not mapped yet.
  if [[ -n "$machine_id" ]] && map_linux_machine_id_to_host "$machine_id"; then
    return 0
  fi

  printf '%s\n' 'linux'
}

case "$(uname -s)" in
  Darwin)
    detect_macos_host
    ;;
  Linux)
    detect_linux_host
    ;;
  *)
    printf '%s\n' "bootstrap: unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac
