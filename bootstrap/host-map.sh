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
# - leave the map empty when the generic base "linux" config is enough

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
  case "${1:-}" in
    # Example:
    # 0123456789abcdef0123456789abcdef)
    #   printf '%s\n' 'linux'
    #   return 0
    #   ;;
    '')
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}
