#!/usr/bin/env bash
set -euo pipefail

repo_url="${HERDR_THEME_REPO:-https://github.com/mi2428/herdr-omarchy-catppuccin.git}"
source_dir="${HERDR_THEME_DIR:-$HOME/io/herdr-omarchy-catppuccin}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app"
herdr_bin="${HERDR_APP_BIN:-$HOME/.local/bin/herdr-app}"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
settings_source="${HERDR_SETTINGS_FILE:-$repo_root/home/files/config/herdr-app/settings.json}"

for tool in git install; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Missing required tool: %s\n' "$tool" >&2
    exit 1
  fi
done
if [[ ! -f "$settings_source" ]]; then
  printf 'Missing managed Herdr settings: %s\n' "$settings_source" >&2
  exit 1
fi

# The layout is a generated install, not a development checkout. Follow the
# repository's default branch so a rerun picks up the latest theme and mods.
if [[ -d "$source_dir/.git" ]]; then
  git -C "$source_dir" fetch --prune origin
  git -C "$source_dir" remote set-head origin --auto >/dev/null 2>&1 || true
  git -C "$source_dir" checkout --detach --quiet origin/HEAD
else
  mkdir -p "$(dirname "$source_dir")"
  git clone --depth 1 "$repo_url" "$source_dir"
fi
commit=$(git -C "$source_dir" rev-parse --short HEAD)
printf 'Herdr Omarchy Catppuccin: %s (%s)\n' "$source_dir" "$commit"

mkdir -p "$config_dir/layouts" "$config_dir/themes"
install -m644 "$source_dir/layouts/omarchy-catppuccin.json" "$config_dir/layouts/omarchy-catppuccin.json"
install -m644 "$source_dir/themes/catppuccin-mocha.json" "$config_dir/themes/catppuccin-mocha.json"
install -m600 "$settings_source" "$config_dir/settings.json"

for mod in "$source_dir"/mods/*; do
  [[ -d "$mod" ]] || continue
  name=$(basename "$mod")
  destination="$config_dir/mods/$name"
  mkdir -p "$destination"
  for file in "$mod"/*.js "$mod"/*.sh "$mod"/*.svg "$mod"/mod.json; do
    [[ -f "$file" ]] || continue
    base=$(basename "$file")
    # Home Manager owns the tabs-files code; keep its symlinks intact while
    # still installing the scripts and icons that sit beside them.
    if [[ "$name" == tabs-files && ("$base" == main.js || "$base" == mod.json) ]]; then
      continue
    fi
    install -m644 "$file" "$destination/$base"
  done
done

if [[ -x "$herdr_bin" ]] && "$herdr_bin" status >/dev/null 2>&1; then
  "$herdr_bin" 'do' layout.switch '{"name":"omarchy-catppuccin"}'
else
  printf 'Herdr app is not running; start it and rerun this task to select omarchy-catppuccin.\n'
fi
