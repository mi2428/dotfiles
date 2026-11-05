#!/usr/bin/env bash

# Keep host identity mapping in one place so detection code only reads platform-specific IDs
# and normalizes them to stable flake keys.
#
# macOS:
# - detect-host.sh reads the hardware serial number
# - add a case here when a new Mac should resolve to a dedicated host key
#
# Linux:
# - detect-host.sh reads /etc/machine-id for non-container systems
# - add a case here when a specific machine-id should resolve to a dedicated host key
# - store only SHA-256 hashes of machine IDs in this public repository

map_macos_serial_to_host() {
  case "${1:-}" in
    C3VH95F6P6)
      printf '%s\n' 'macos'
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

map_linux_machine_id_to_host() {
  case "$(printf '%s' "${1:-}" | sha256sum | cut -d ' ' -f 1)" in
    fc17a89aa012b8f7294aa060bc16bc52f7a0a254d575c20ef67de2e1cbeb0cbb)
      printf '%s\n' 'omarchy'
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
