#!/usr/bin/env bash

set -euo pipefail

current_command="${1:-}"
current_path="${2:-}"
default_shell="${3:-}"

current_command="${current_command##*/}"
default_shell="${default_shell##*/}"

if [[ -z "$current_command" ]]; then
  current_command="$default_shell"
fi

if [[ "$current_command" == "$default_shell" ]]; then
  home="${HOME:-}"

  if [[ -n "$home" && "$current_path" == "$home" ]]; then
    printf '~\n'
    exit 0
  fi

  if [[ -n "$home" && "$current_path" == "$home/"* ]]; then
    printf '~/%s\n' "${current_path#"$home/"}"
    exit 0
  fi

  if [[ -n "$current_path" ]]; then
    printf '%s\n' "$current_path"
    exit 0
  fi
fi

printf '%s\n' "$current_command"
