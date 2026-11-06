#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-presets.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/repo/"{scripts,bootstrap,home/files/config/hypr/omarchy,home/files/config/ghostty} "$scratch/bin"
cp "$root/scripts/copy-omarchy-presets.sh" "$scratch/repo/scripts/"
cat >"$scratch/repo/bootstrap/detect-host.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "${TEST_HOST:-omarchy}"
EOF
printf '#!/bin/sh\nprintf "Linux\\n"\n' >"$scratch/bin/uname"
chmod +x "$scratch/repo/bootstrap/detect-host.sh" "$scratch/bin/uname"
export PATH="$scratch/bin:$PATH" XDG_CONFIG_HOME="$scratch/config"
for name in input bindings monitors; do
  printf '%s preset\n' "$name" >"$scratch/repo/home/files/config/hypr/omarchy/$name.lua"
done
echo 'font-family = Summer Ghost' >"$scratch/repo/home/files/config/ghostty/config.ghostty"
mkdir -p "$XDG_CONFIG_HOME/hypr" "$XDG_CONFIG_HOME/omarchy"
echo 'world clock stays enabled' >"$XDG_CONFIG_HOME/omarchy/shell.json"
echo 'immutable original' >"$scratch/immutable"
chmod 0444 "$scratch/immutable"
ln -s "$scratch/immutable" "$XDG_CONFIG_HOME/hypr/input.lua"

if TEST_HOST=linux bash "$scratch/repo/scripts/copy-omarchy-presets.sh" >/dev/null 2>&1; then
  echo 'Unregistered host was accepted' >&2
  exit 1
fi
test -L "$XDG_CONFIG_HOME/hypr/input.lua"

# The copier deliberately uses Linux coreutils (mv -T); mock only that spelling
# on macOS so the same offline check can run on both platforms.
if [[ $(/usr/bin/uname -s) == Darwin ]]; then
  cat >"$scratch/bin/mv" <<'EOF'
#!/bin/sh
test "$1" = -fT
shift
exec /bin/mv -f "$@"
EOF
  chmod +x "$scratch/bin/mv"
fi
bash "$scratch/repo/scripts/copy-omarchy-presets.sh" >/dev/null
test ! -L "$XDG_CONFIG_HOME/hypr/input.lua"
test -w "$XDG_CONFIG_HOME/hypr/input.lua"
test "$(cat "$scratch/immutable")" = 'immutable original'
test "$(cat "$XDG_CONFIG_HOME"/hypr/input.lua.before-dotfiles.*)" = 'immutable original'
cmp "$XDG_CONFIG_HOME/ghostty/config" "$scratch/repo/home/files/config/ghostty/config.ghostty"
test "$(cat "$XDG_CONFIG_HOME/omarchy/shell.json")" = 'world clock stays enabled'

# Ordinary switches never call this explicit copier; local edits remain until
# requested. An explicit second copy saves those edits before replacing them.
echo 'local edit' >"$XDG_CONFIG_HOME/hypr/bindings.lua"
bash "$scratch/repo/scripts/copy-omarchy-presets.sh" >/dev/null
test "$(cat "$XDG_CONFIG_HOME"/hypr/bindings.lua.before-dotfiles.*)" = 'local edit'

echo 'keep this' >"$XDG_CONFIG_HOME/hypr/input.lua"
for invalid in directory dangling; do
  rm -rf "$XDG_CONFIG_HOME/ghostty/config"
  case "$invalid" in
    directory) mkdir "$XDG_CONFIG_HOME/ghostty/config" ;;
    dangling) ln -s "$scratch/missing" "$XDG_CONFIG_HOME/ghostty/config" ;;
  esac
  if bash "$scratch/repo/scripts/copy-omarchy-presets.sh" >/dev/null 2>&1; then
    echo "Invalid target accepted: $invalid" >&2
    exit 1
  fi
  test "$(cat "$XDG_CONFIG_HOME/hypr/input.lua")" = 'keep this'
done
rm "$XDG_CONFIG_HOME/ghostty/config"
rm "$scratch/repo/home/files/config/ghostty/config.ghostty"
if bash "$scratch/repo/scripts/copy-omarchy-presets.sh" >/dev/null 2>&1; then
  echo 'Missing preset was accepted' >&2
  exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/hypr/input.lua")" = 'keep this'
printf '%s\n' 'Omarchy writable presets and backups: ok'
