#!/bin/bash
set -euo pipefail

FISH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
FISH_PLUGINS_FILE="$FISH_CONFIG_DIR/fish_plugins"
FISH_FROZEN_THEME_FILE="$FISH_CONFIG_DIR/conf.d/fish_frozen_theme.fish"

if ! command -v fish >/dev/null 2>&1; then
  exit 0
fi

if [[ ! -f "$FISH_PLUGINS_FILE" ]]; then
  exit 0
fi

# Fish 4.3+ migrated theme handling away from this compatibility shim.
rm -f "$FISH_FROZEN_THEME_FILE"

MANIFEST_CONTENT="$(cat "$FISH_PLUGINS_FILE")"

if ! fish -c 'type -q fisher' >/dev/null 2>&1; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "setup-fish-plugins: curl is required to bootstrap fisher." >&2
    exit 1
  fi
  fish -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source; fisher install jorgebucaran/fisher'
fi

desired_plugins=()
while IFS= read -r plugin; do
  desired_plugins+=("$plugin")
done < <(awk '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  { print $0 }
' "$FISH_PLUGINS_FILE")

installed_plugins=()
while IFS= read -r plugin; do
  installed_plugins+=("$plugin")
done < <(fish -c 'fisher list')

plugins_to_install=()
for plugin in "${desired_plugins[@]}"; do
  plugin_lc="$(printf '%s' "$plugin" | tr '[:upper:]' '[:lower:]')"
  installed_match=false
  for installed_plugin in "${installed_plugins[@]}"; do
    installed_plugin_lc="$(printf '%s' "$installed_plugin" | tr '[:upper:]' '[:lower:]')"
    if [[ "$installed_plugin_lc" == "$plugin_lc" ]]; then
      installed_match=true
      break
    fi
  done

  if [[ "$installed_match" == false ]]; then
    plugins_to_install+=("$plugin")
  fi
done

plugins_to_remove=()
for plugin in "${installed_plugins[@]}"; do
  plugin_lc="$(printf '%s' "$plugin" | tr '[:upper:]' '[:lower:]')"
  desired_match=false
  for desired_plugin in "${desired_plugins[@]}"; do
    desired_plugin_lc="$(printf '%s' "$desired_plugin" | tr '[:upper:]' '[:lower:]')"
    if [[ "$desired_plugin_lc" == "$plugin_lc" ]]; then
      desired_match=true
      break
    fi
  done

  if [[ "$desired_match" == false ]]; then
    plugins_to_remove+=("$plugin")
  fi
done

if [[ ${#plugins_to_install[@]} -gt 0 ]]; then
  fish -c "fisher install ${plugins_to_install[*]}"
fi

if [[ ${#plugins_to_remove[@]} -gt 0 ]]; then
  fish -c "fisher remove ${plugins_to_remove[*]}"
fi

fish -c 'fisher update'

printf '%s\n' "$MANIFEST_CONTENT" > "$FISH_PLUGINS_FILE"
