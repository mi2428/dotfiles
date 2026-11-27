#!/bin/sh
set -eu

errors=0
fail() {
    printf 'error: %s\n' "$1" >&2
    errors=$((errors + 1))
}

for program in opencode opencode-profile opencode-happier happier custom-acp herdr codex claude omp omo oc-slim-service; do
    command -v "$program" >/dev/null 2>&1 || fail "$program is not installed"
done

for file in config.yml models.yml AGENTS.md RULES.md themes/catppuccin-mocha-mauve.json; do
    [ -f "$HOME/.omp/agent/$file" ] || fail "OMP configuration is missing: $file"
done
[ ! -L "$HOME/.omp/agent/config.yml" ] || fail 'OMP config.yml must be a writable regular file'
[ -w "$HOME/.omp/agent/config.yml" ] || fail 'OMP config.yml is not writable'
[ -f "$HOME/.omp/agent/extensions/herdr-omp-agent-state.ts" ] || fail 'Herdr OMP integration is missing'

for file in "$HOME/.omo/omo.jsonc" "$HOME/.omo/agent/models.json" "$HOME/.omo/agent/settings.json"; do
    [ -f "$file" ] || fail "OMO configuration is missing: $file"
    [ ! -L "$file" ] || fail "OMO configuration must be a writable regular file: $file"
    [ -w "$file" ] || fail "OMO configuration is not writable: $file"
done
[ -f "$HOME/.omo/agent/themes/catppuccin-mocha.json" ] || fail 'OMO Catppuccin theme is missing'
jq -e '.theme == "catppuccin-mocha"' "$HOME/.omo/agent/settings.json" >/dev/null ||
    fail 'OMO theme is not catppuccin-mocha'
[ -f "$HOME/.config/mise/conf.d/50-dotfiles-ai.toml" ] || fail 'mise omo-ai declaration is missing'

if command -v omo >/dev/null 2>&1; then
    for model in preview/GLM-5.3-Flash preview/DeepSeek-V4.1-Flash-1017; do
        omo auth check --provider sakura --model "$model" >/dev/null 2>&1 ||
            fail "OMO Sakura model is not ready: $model"
    done
fi

# oh-my-opencode-slim 3.0.8 requires OpenCode 2.3 or newer.
if command -v opencode >/dev/null 2>&1; then
    version=$(opencode --version 2>/dev/null) || version=
    printf '%s\n' "$version" | grep -Eq '(^|[[:space:]])v?2\.(3|[4-9]|[1-9][0-9]+)\.[0-9]+$' ||
        fail "OpenCode 2.3.0 or newer is required (found: ${version:-unknown})"
fi

for profile in chat happier herdr slim; do
    config="$HOME/.config/opencode-profiles/$profile/opencode"
    [ -f "$config/opencode.jsonc" ] && [ -f "$config/cli.json" ] ||
        fail "OpenCode $profile profile is not installed"
    [ -f "$config/themes/catppuccin-mocha-mauve.json" ] ||
        fail "OpenCode $profile custom theme is missing"
done

# Slim uses a profile-local shared service for Herdr App panes.
slim_service="$HOME/.config/opencode-profiles/slim/opencode/service.json"
[ -f "$slim_service" ] || fail 'Slim service config is missing'
jq -e '.port == 4099' "$slim_service" >/dev/null ||
    fail 'Slim service port is not 4099'

happier_cli="$HOME/.config/opencode-profiles/happier/opencode/cli.json"
jq -e '.session.permissions == "autoaccept"' "$happier_cli" >/dev/null ||
    fail 'Happier OpenCode must auto-approve permissions'

herdr_config="$HOME/.config/opencode-profiles/herdr/opencode"
for plugin in \
    "$herdr_config/herdr-opencode/tui.js" \
    "$herdr_config/herdr-tui-session.js" \
    "$herdr_config/tui-plugins/todo/lib/herdr-views.ts" \
    "$herdr_config/plugins/session-title.js"; do
    [ -f "$plugin" ] || fail "Herdr OpenCode plugin is missing: $plugin"
done
for plugin in "$herdr_config/plugins/herdr-shell-env.js" "$herdr_config/plugins/session-title.js"; do
    [ ! -L "$plugin" ] || fail "Herdr OpenCode server plugin must be a regular file: $plugin"
done
for config in "$HOME/.config/opencode" "$herdr_config" "$HOME/.config/opencode-profiles/slim/opencode"; do
    for agent in herdr-supervisor herdr-worker; do
        [ ! -e "$config/agents/$agent.md" ] || fail "Obsolete Herdr primary agent remains: $agent"
    done
done
for config in "$HOME/.config/opencode" "$HOME/.config/opencode-profiles/chat/opencode" "$HOME/.config/opencode-profiles/slim/opencode"; do
    plugin="$config/plugins/session-title.js"
    [ -f "$plugin" ] && [ ! -L "$plugin" ] || fail "OpenCode session title plugin is not installed as a regular file: $plugin"
done

if command -v herdr >/dev/null 2>&1; then
    herdr config check >/dev/null 2>&1 || fail 'Herdr config is invalid'
fi

[ "$errors" -eq 0 ] || exit 1
printf '%s\n' 'AI stack check passed.'
