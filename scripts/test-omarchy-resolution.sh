#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-resolution.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/config/hypr"
export XDG_CONFIG_HOME="$scratch/config" RESOLUTION_TEST_DIR="$scratch"
cp "$root/home/files/config/hypr/omarchy/monitors.lua" "$XDG_CONFIG_HOME/hypr/monitors.lua"
printf '2704\n' >"$scratch/width"
cat >"$scratch/bin/hyprctl" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = instances ]; then
  printf '[{"instance":"test-session"}]\n'
  exit 0
fi
test "$1" = -i && test "$2" = test-session
case "$3" in
  monitors)
    jq -n --argjson width "$(cat "$RESOLUTION_TEST_DIR/width")" \
      '[{name:"eDP-1",width:3024,height:1964,scale:(3024/$width),mirrorOf:"none",disabled:false}]'
    ;;
  reload)
    if [ "${FAIL_RELOAD:-0}" = 1 ]; then exit 1; fi
    sed -n 's/^local logical_width = //p' "$XDG_CONFIG_HOME/hypr/monitors.lua" >"$RESOLUTION_TEST_DIR/width"
    ;;
esac
EOF
chmod +x "$scratch/bin/hyprctl"
# The command intentionally uses Linux coreutils; use GNU tools on macOS too.
if [[ $(uname -s) == Darwin ]]; then
  for tool in chmod cp mv; do
    command -v "g$tool" >/dev/null
    ln -s "$(command -v "g$tool")" "$scratch/bin/$tool"
  done
fi
export PATH="$scratch/bin:$PATH"
config="$XDG_CONFIG_HOME/hypr/monitors.lua"
printf '\n-- Preserve local adjustments.\n' >>"$config"
original=$(cat "$config")
for width in 3024 2294 2704; do
  bash "$root/bin/omarchy-resolution-toggle" >/dev/null
  test "$(cat "$scratch/width")" = "$width"
  grep -qxF "local logical_width = $width" "$config"
done
test "$(cat "$config")" = "$original"
if FAIL_RELOAD=1 bash "$root/bin/omarchy-resolution-toggle" >/dev/null 2>&1; then
  echo 'Failed reload was accepted' >&2
  exit 1
fi
test "$(cat "$config")" = "$original"
printf '2000\n' >"$scratch/width"
if bash "$root/bin/omarchy-resolution-toggle" >/dev/null 2>&1; then
  echo 'Unknown display size was accepted' >&2
  exit 1
fi
test "$(cat "$config")" = "$original"
printf '2704\n' >"$scratch/width"
sed 's/^local logical_width = .*/local another_setting = 2704/' "$config" >"$scratch/invalid.lua"
mv "$scratch/invalid.lua" "$config"
invalid=$(cat "$config")
if bash "$root/bin/omarchy-resolution-toggle" >/dev/null 2>&1; then
  echo 'Unknown monitor config was accepted' >&2
  exit 1
fi
test "$(cat "$config")" = "$invalid"
printf '%s\n' 'Persistent three-preset display cycle and rollback: ok'
