#!/bin/sh
set -eu

errors=0
fail() {
    printf 'error: %s\n' "$1" >&2
    errors=$((errors + 1))
}

for program in opencode opencode-profile opencode-happier herdr codex claude omp; do
    command -v "$program" >/dev/null 2>&1 || fail "$program is not installed"
done

for file in .env config.yml models.yml AGENTS.md RULES.md themes/catppuccin-mocha-mauve.json; do
    [ -f "$HOME/.omp/agent/$file" ] || fail "OMP configuration is missing: $file"
done
[ ! -L "$HOME/.omp/agent/config.yml" ] || fail 'OMP config.yml must be a writable regular file'
[ -w "$HOME/.omp/agent/config.yml" ] || fail 'OMP config.yml is not writable'
[ -f "$HOME/.omp/agent/extensions/herdr-omp-agent-state.ts" ] || fail 'Herdr OMP integration is missing'

if command -v opencode >/dev/null 2>&1; then
    version=$(opencode --version 2>/dev/null) || version=
    printf '%s\n' "$version" | grep -Eq '(^|[[:space:]])v?2\.([2-9]|[1-9][0-9]+)\.[0-9]+$' ||
        fail "OpenCode 2.2.0 or newer is required (found: ${version:-unknown})"
fi

for profile in chat happier herdr slim; do
    config="$HOME/.config/opencode-profiles/$profile/opencode"
    [ -f "$config/opencode.jsonc" ] && [ -f "$config/cli.json" ] ||
        fail "OpenCode $profile profile is not installed"
    [ -f "$config/themes/catppuccin-mocha-mauve.json" ] ||
        fail "OpenCode $profile custom theme is missing"
done

happier_cli="$HOME/.config/opencode-profiles/happier/opencode/cli.json"
jq -e '.session.permissions == "autoaccept"' "$happier_cli" >/dev/null ||
    fail 'Happier OpenCode must auto-approve permissions'

herdr_config="$HOME/.config/opencode-profiles/herdr/opencode"
for plugin in \
    "$herdr_config/herdr-opencode/tui.js" \
    "$herdr_config/herdr-tui-session.js" \
    "$herdr_config/plugins/herdr-agent-state.js" \
    "$herdr_config/plugins/session-title.js"; do
    [ -f "$plugin" ] || fail "Herdr OpenCode plugin is missing: $plugin"
done
for plugin in "$herdr_config/plugins/herdr-agent-state.js" "$herdr_config/plugins/session-title.js"; do
    [ ! -L "$plugin" ] || fail "Herdr OpenCode server plugin must be a regular file: $plugin"
done
for config in "$HOME/.config/opencode" "$HOME/.config/opencode-profiles/chat/opencode" "$HOME/.config/opencode-profiles/slim/opencode"; do
    plugin="$config/plugins/session-title.js"
    [ -f "$plugin" ] && [ ! -L "$plugin" ] || fail "OpenCode session title plugin is not installed as a regular file: $plugin"
done

if command -v herdr >/dev/null 2>&1; then
    herdr config check >/dev/null 2>&1 || fail 'Herdr config is invalid'
    if [ "${HERDR_ENV:-}" = 1 ]; then
        herdr plugin list --plugin mi2428.agent-layout --json 2>/dev/null |
            jq -e '.result.plugins | any(.plugin_id == "mi2428.agent-layout" and .enabled == true)' >/dev/null ||
            fail 'Herdr Agent Layout plugin is not enabled'
    fi
fi

[ "$errors" -eq 0 ] || exit 1
printf '%s\n' 'AI stack check passed.'
