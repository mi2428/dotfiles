#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/bin" "$tmp/config/opencode"
printf '{}\n' > "$tmp/config/opencode/opencode.jsonc"
cat > "$tmp/bin/hc" <<'EOF'
#!/bin/sh
printf '%s\n' '{"state":"live","labels":{"herdr.space":"sp1","herdr.tab":"tb1"}}'
EOF
cat > "$tmp/bin/opencode" <<'EOF'
#!/bin/sh
if [ "${OPENCODE_CONFIG_CONTENT+x}" = x ] || [ "${OPENCODE_CLI_CONFIG_CONTENT+x}" = x ]; then
    echo 'inherited inline config escaped profile isolation' >&2; exit 1
fi
printf '%s\n' "$@" > "$HC_TEST_OUTPUT"
EOF
chmod +x "$tmp/bin/hc" "$tmp/bin/opencode"
export PATH="$tmp/bin:$PATH" OPENCODE_PROFILE_CONFIG_HOME="$tmp/config" HC_TERMINAL_ID=t2 HC_TEST_OUTPUT="$tmp/result"
unset HERDR_ENV

OPENCODE_CONFIG_CONTENT='{"default_agent":"chat"}' OPENCODE_CLI_CONFIG_CONTENT='{"plugins":[]}' \
    "$root/scripts/opencode-profile.sh" hc --auto
[ "$(cat "$tmp/result")" = --auto ] || {
    echo 'hc changed launch arguments or selected a standalone server' >&2; exit 1
}
if HERDR_ENV=1 "$root/scripts/opencode-profile.sh" hc > /dev/null 2>&1; then
    echo 'mixed Herdr/hc identity was accepted' >&2; exit 1
fi
echo 'hc profile checks passed'
