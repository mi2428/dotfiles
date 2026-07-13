#!/usr/bin/env bash

set -euo pipefail

current_command="${1:-}"
current_path="${2:-}"
default_shell="${3:-}"

shorten_path() {
  local path="$1"
  local prefix="" rest=""
  local -a parts=() shortened=()
  local part=""
  local tilde_home="~"
  local tilde_home_prefix

  tilde_home_prefix="$(printf '%s/' "$tilde_home")"

  if [[ -z "$path" ]]; then
    return
  fi

  if [[ "$path" == "$tilde_home" ]]; then
    printf '%s\n' "$tilde_home"
    return
  fi

  if [[ $path == \~/* ]]; then
    prefix="$tilde_home_prefix"
    rest="${path:2}"
  elif [[ "$path" == /* ]]; then
    prefix="/"
    rest="${path#/}"
  else
    rest="$path"
  fi

  IFS='/' read -r -a parts <<< "$rest"

  if [[ "${#parts[@]}" -eq 0 ]]; then
    printf '%s\n' "$path"
    return
  fi

  for ((i = 0; i < ${#parts[@]}; i++)); do
    part="${parts[i]}"
    if [[ -z "$part" ]]; then
      continue
    fi

    if (( i == ${#parts[@]} - 1 )); then
      shortened+=("$part")
    else
      shortened+=("${part:0:1}")
    fi
  done

  if [[ "${#shortened[@]}" -eq 0 ]]; then
    printf '%s\n' "$prefix"
    return
  fi

  printf '%s%s\n' "$prefix" "$(IFS=/; printf '%s' "${shortened[*]}")"
}

current_command="${current_command##*/}"
default_shell="${default_shell##*/}"

if [[ -z "$current_command" ]]; then
  current_command="$default_shell"
fi

if [[ -n "$current_path" ]]; then
  home="${HOME:-}"
  command_prefix="$current_command"

  if [[ "$current_command" == "$default_shell" ]]; then
    command_prefix=""
  fi

  if [[ -n "$home" && "$current_path" == "$home" ]]; then
    printf '%s~\n' "$command_prefix"
    exit 0
  fi

  if [[ -n "$home" && "$current_path" == "$home/"* ]]; then
    if [[ -n "$command_prefix" ]]; then
      printf '%s ' "$command_prefix"
    fi
    shorten_path "$(printf '%s/%s' "~" "${current_path#"$home/"}")"
    exit 0
  fi

  if [[ -n "$command_prefix" ]]; then
    printf '%s ' "$command_prefix"
  fi
  shorten_path "$current_path"
  exit 0
fi

printf '%s\n' "$current_command"
