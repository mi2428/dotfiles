#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
failures=0

ok() {
    printf 'ok: %s\n' "$1"
}

fail() {
    printf 'error: %s\n' "$1" >&2
    failures=$((failures + 1))
}

warn() {
    printf 'warning: %s\n' "$1" >&2
}

require_command() {
    label=$1
    command_name=$2
    if command -v "$command_name" >/dev/null 2>&1; then
        command_path=$(command -v "$command_name")
        ok "$label: $command_path"
    else
        fail "$label is not installed ($command_name)"
    fi
}

require_brewfile_entry() {
    entry=$1
    if grep -Fqx "$entry" "$repo_root/Brewfile"; then
        ok "Brewfile declares $entry"
    else
        fail "Brewfile does not declare $entry"
    fi
}

require_command OpenCode opencode
require_command Codex codex
require_command 'Claude Code' claude
require_command Herdr herdr
require_command jq jq
require_command curl curl

if [ "$(uname -s)" = Darwin ]; then
    require_brewfile_entry 'brew "anomalyco/tap/opencode", trusted: true'
    require_brewfile_entry 'brew "herdr"'
    require_brewfile_entry 'cask "codex"'
    require_brewfile_entry 'cask "claude-code"'
fi

if command -v opencode >/dev/null 2>&1; then
    ok "OpenCode $(opencode --version)"
fi
if command -v codex >/dev/null 2>&1; then
    ok "$(codex --version)"
fi
if command -v claude >/dev/null 2>&1; then
    ok "Claude Code $(claude --version)"
fi
if command -v herdr >/dev/null 2>&1; then
    ok "Herdr $(herdr --version)"
fi

plugin_versions="$repo_root/home/files/config/opencode/plugin-versions.json"
omo_version=$(jq -er '.omo' "$plugin_versions")
slim_version=$(jq -er '.slim' "$plugin_versions")
omo_plugin_spec="oh-my-openagent@$omo_version"
slim_plugin_spec="oh-my-opencode-slim@$slim_version"
default_plugin_config="$HOME/.config/opencode/opencode.jsonc"
default_tui_config="$HOME/.config/opencode/tui.json"
omo_config="$repo_root/home/files/omo/omo.jsonc"
chat_config_home="$HOME/.config/opencode-profiles/chat"
chat_root="$chat_config_home/opencode"

for pin in "OmO:$omo_plugin_spec:$omo_version" "Slim:$slim_plugin_spec:$slim_version"; do
    label=${pin%%:*}
    remainder=${pin#*:}
    plugin_spec=${remainder%%:*}
    version=${remainder#*:}
    if printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)*$'; then
        ok "OpenCode pins $plugin_spec"
    else
        fail "OpenCode $label plugin pin is not an exact version: $plugin_spec"
    fi
done

check_npm_plugin_version() {
    package=$1
    version=$2
    if [ -n "$version" ] \
        && curl -fsSL "https://registry.npmjs.org/${package}/${version}" \
            | jq -e --arg package "$package" --arg version "$version" \
                '.name == $package and .version == $version' >/dev/null; then
        ok "npm publishes $package@$version"
    else
        fail "npm does not publish $package@$version"
    fi
}

check_npm_plugin_version oh-my-openagent "$omo_version"
check_npm_plugin_version oh-my-opencode-slim "$slim_version"

default_root_clean=true
for config in "$default_plugin_config" "$default_tui_config"; do
    if [ ! -f "$config" ]; then
        fail "the default OpenCode config is missing: $config"
        default_root_clean=false
        continue
    fi
    if grep -Fq 'oh-my-openagent' "$config" || grep -Fq 'oh-my-opencode-slim' "$config"; then
        default_root_clean=false
    fi
done
if [ "$default_root_clean" = true ]; then
    ok "the default OpenCode config root stays framework-plugin-free"
else
    fail "the default OpenCode config root contains a framework plugin reference"
fi
if [ -f "$default_tui_config" ] \
    && jq -e '.plugin | index("./plugins/tui") != null' "$default_tui_config" >/dev/null; then
    ok 'the default OpenCode TUI loads the shared Todo plugin'
else
    fail 'the default OpenCode TUI does not load the shared Todo plugin'
fi

schema_url=$(awk -F'"' '/"[$]schema"/ { print $4; exit }' "$omo_config")
expected_schema_url="https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/v${omo_version}/assets/omo.schema.json"
if [ -n "$omo_version" ] && [ "$schema_url" = "$expected_schema_url" ]; then
    ok "OmO schema matches v$omo_version"
else
    fail "OmO schema URL does not match the plugin pin ($schema_url)"
fi

if [ -n "$schema_url" ]; then
    if curl -fsSL "$schema_url" | jq -e . >/dev/null; then
        ok "OmO schema is reachable and valid JSON"
    else
        fail "OmO schema is unreachable or invalid: $schema_url"
    fi
fi

check_resolved_plugin_config() {
    profile_name=$1
    profile_id=$2
    plugin_spec=$3
    profile_config_home="$HOME/.config/opencode-profiles/$profile_id"
    profile_root="$profile_config_home/opencode"
    if resolved_config=$(XDG_CONFIG_HOME="$profile_config_home" opencode debug config --pure 2>/dev/null); then
        resolved_plugin=$(printf '%s\n' "$resolved_config" | jq -r --arg spec "$plugin_spec" '.plugin[]? | select(. == $spec)' | head -n 1)
        if [ "$resolved_plugin" = "$plugin_spec" ]; then
            ok "OpenCode resolves the pinned $profile_name plugin config"
        else
            fail "OpenCode resolved $profile_name config does not contain $plugin_spec"
        fi
    else
        fail "OpenCode could not resolve the installed $profile_name profile"
    fi

    if jq -e --arg spec "$plugin_spec" \
        '.plugin | index($spec) != null and index("./plugins/tui") != null' \
        "$profile_root/tui.json" >/dev/null; then
        ok "OpenCode $profile_name TUI loads its framework and shared Todo plugin"
    else
        fail "OpenCode $profile_name TUI plugin registry is incomplete"
    fi

    if [ -f "$profile_root/plugins/profile-shell-env.js" ]; then
        ok "OpenCode $profile_name restores the caller XDG root for shell tools"
    else
        fail "OpenCode $profile_name profile shell environment plugin is missing"
    fi
}

if command -v opencode >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    check_resolved_plugin_config OmO omo "$omo_plugin_spec"
    check_resolved_plugin_config Slim slim "$slim_plugin_spec"

    if chat_config=$(
        XDG_CONFIG_HOME="$chat_config_home" \
            OPENCODE_DISABLE_PROJECT_CONFIG=1 \
            OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
            OPENCODE_DISABLE_CLAUDE_CODE=1 \
            opencode debug config 2>/dev/null
    ); then
        if printf '%s\n' "$chat_config" | jq -e '
            .default_agent == "Chat"
            and .agent.Chat.mode == "primary"
            and .agent.build.disable == true
            and .agent.plan.disable == true
            and .agent.general.disable == true
            and .agent.explore.disable == true
            and .permission.external_directory["*"] == "deny"
        ' >/dev/null; then
            ok 'OpenCode Chat profile exposes only the Chat primary agent'
        else
            fail 'OpenCode Chat profile agent isolation is incomplete'
        fi
        if printf '%s\n' "$chat_config" \
            | jq -e '[.plugin[]? | select(endswith("/chat-system.js"))] | length == 1' >/dev/null; then
            ok 'OpenCode Chat profile loads its system prompt plugin'
        else
            fail 'OpenCode Chat profile system prompt plugin is missing'
        fi
    else
        fail 'OpenCode could not resolve the installed Chat profile'
    fi

    if jq -e '
        .keybinds.agent_list == "none"
        and .keybinds.agent_cycle == "none"
        and .keybinds.agent_cycle_reverse == "none"
    ' "$chat_root/tui.json" >/dev/null; then
        ok 'OpenCode Chat TUI disables agent switching'
    else
        fail 'OpenCode Chat TUI still allows agent switching'
    fi

    if XDG_CONFIG_HOME="$HOME/.config" OPENCODE_DISABLE_PROJECT_CONFIG=1 \
        opencode debug config 2>/dev/null | jq -e '.agent.Chat == null' >/dev/null; then
        ok 'the default OpenCode profile does not expose Chat'
    else
        fail 'the default OpenCode profile exposes Chat'
    fi
fi

if command -v herdr >/dev/null 2>&1; then
    integration_status=$(herdr integration status)
    for target in claude codex opencode; do
        status_line=$(printf '%s\n' "$integration_status" | grep "^${target}:" || true)
        case "$status_line" in
            "$target: current "*) ok "Herdr $status_line" ;;
            *) fail "Herdr integration is not current: ${status_line:-$target: missing}" ;;
        esac
    done
fi

integration_source="$HOME/.config/opencode/plugins/herdr-agent-state.js"
if [ -f "$integration_source" ]; then
    ok "Herdr OpenCode integration exists"
    for profile in chat omo slim; do
        profile_integration="$HOME/.config/opencode-profiles/$profile/opencode/plugins/herdr-agent-state.js"
        if [ -e "$profile_integration" ] && [ "$profile_integration" -ef "$integration_source" ]; then
            ok "OpenCode $profile profile links the Herdr integration"
        else
            fail "OpenCode $profile profile does not link $integration_source"
        fi
    done
else
    fail "Herdr OpenCode integration is missing: $integration_source"
    for profile in chat omo slim; do
        profile_integration="$HOME/.config/opencode-profiles/$profile/opencode/plugins/herdr-agent-state.js"
        if [ -L "$profile_integration" ] && [ ! -e "$profile_integration" ]; then
            fail "OpenCode $profile profile contains a dangling Herdr integration"
        fi
    done
fi

for skill_path in \
    "$HOME/.agents/skills/herdr-agent-layout" \
    "$HOME/.claude/skills/herdr-agent-layout"; do
    if [ -f "$skill_path/SKILL.md" ]; then
        ok "Herdr agent-layout skill is installed at $skill_path"
    else
        fail "Herdr agent-layout skill is missing: $skill_path"
    fi
done
if command -v opencode >/dev/null 2>&1 \
    && opencode debug skill --pure 2>/dev/null \
        | jq -e '[.[] | select(.name == "herdr-agent-layout")] | length == 1' >/dev/null; then
    ok 'OpenCode discovers exactly one managed Herdr agent-layout skill'
else
    fail 'OpenCode does not discover exactly one Herdr agent-layout skill'
fi

slim_seed="$HOME/.config/opencode-profiles/slim/opencode/oh-my-opencode-slim.seed.jsonc"
slim_runtime="$HOME/.config/opencode-profiles/slim/opencode/oh-my-opencode-slim.jsonc"
if [ ! -f "$slim_seed" ] || [ ! -f "$slim_runtime" ]; then
    fail 'OpenCode Slim managed seed or writable runtime config is missing'
elif cmp -s "$slim_seed" "$slim_runtime"; then
    ok 'OpenCode Slim runtime config matches its managed seed'
else
    warn "OpenCode Slim runtime config has local /preset drift; run 'oc-slim-config status' to inspect"
fi

if [ "$failures" -ne 0 ]; then
    printf 'AI stack check failed with %s error(s).\n' "$failures" >&2
    exit 1
fi

printf 'AI stack check passed.\n'
