#!/bin/sh
set -eu

errors=0
fail() {
    printf 'error: %s\n' "$1" >&2
    errors=$((errors + 1))
}

for program in opencode opencode-profile herdr codex claude; do
    command -v "$program" >/dev/null 2>&1 || fail "$program is not installed"
done

if command -v opencode >/dev/null 2>&1; then
    version=$(opencode --version 2>/dev/null) || version=
    printf '%s\n' "$version" | grep -Eq '(^|[[:space:]])v?2\.([2-9]|[1-9][0-9]+)\.[0-9]+$' ||
        fail "OpenCode 2.2.0 or newer is required (found: ${version:-unknown})"
fi

for profile in chat herdr slim; do
    config="$HOME/.config/opencode-profiles/$profile/opencode"
    [ -f "$config/opencode.jsonc" ] && [ -f "$config/cli.json" ] ||
        fail "OpenCode $profile profile is not installed"
done

herdr_config="$HOME/.config/opencode-profiles/herdr/opencode"
for plugin in \
    "$herdr_config/herdr-opencode/tui.js" \
    "$herdr_config/herdr-tui-session.js" \
    "$herdr_config/plugins/herdr-agent-state/index.js"; do
    [ -f "$plugin" ] || fail "Herdr OpenCode plugin is missing: $plugin"
done

if command -v herdr >/dev/null 2>&1; then
    herdr config check >/dev/null 2>&1 || fail 'Herdr config is invalid'
fi

[ "$errors" -eq 0 ] || exit 1
printf '%s\n' 'AI stack check passed.'
