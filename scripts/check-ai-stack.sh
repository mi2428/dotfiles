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

require_command 'OpenCode V2 launcher' opencode-v2
require_command npm npm
require_command Codex codex
require_command 'Claude Code' claude
require_command Herdr herdr
require_command jq jq
require_command curl curl

if [ "$(uname -s)" = Darwin ]; then
    require_brewfile_entry 'brew "anomalyco/tap/opencode-v2", trusted: true'
    require_brewfile_entry 'brew "herdr"'
    require_brewfile_entry 'cask "codex"'
    require_brewfile_entry 'cask "claude-code"'
fi

if runtime_version=$(opencode-v2 --version); then
    ok "installed OpenCode runtime $runtime_version"
else
    fail 'installed OpenCode runtime must be stable V2.2.0 or newer'
fi

if target_version=$(npm exec --yes --package=@opencode/cli@2.2.0 -- opencode2 --version 2>/dev/null); then
    case "$target_version" in
        *'v2.2.0' | *' 2.2.0') ok "isolated OpenCode target $target_version" ;;
        *) fail "isolated OpenCode target has an unexpected version: $target_version" ;;
    esac
else
    fail 'could not run isolated OpenCode target @opencode/cli@2.2.0'
fi
if command -v codex >/dev/null 2>&1; then
    ok "$(codex --version)"
fi
if command -v claude >/dev/null 2>&1; then
    ok "Claude Code $(claude --version)"
fi
if command -v herdr >/dev/null 2>&1; then
    ok "Herdr $(herdr --version)"
    if herdr_config_status=$(herdr config check 2>&1); then
        ok "Herdr config is valid"
    else
        fail "Herdr config is invalid: $herdr_config_status"
    fi
fi

plugin_versions="$repo_root/home/files/config/opencode/plugin-versions.json"
omo_version=$(jq -er '.omo' "$plugin_versions")
slim_version=$(jq -er '.slim' "$plugin_versions")
omo_plugin_spec="oh-my-openagent@$omo_version"
slim_plugin_spec="oh-my-opencode-slim@$slim_version"
default_config_home="$HOME/.config"
default_cli_config="$default_config_home/opencode/cli.json"
omo_config="$repo_root/home/files/omo/omo.jsonc"
chat_config_home="$HOME/.config/opencode-profiles/chat"
omo_config_home="$HOME/.config/opencode-profiles/omo"
slim_config_home="$HOME/.config/opencode-profiles/slim"

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

slim_base=${slim_version%%[-+]*}
slim_major=${slim_base%%.*}
slim_rest=${slim_base#*.}
slim_minor=${slim_rest%%.*}
slim_patch=${slim_rest#*.}
case "$slim_major:$slim_minor:$slim_patch" in
    *[!0-9:]* | :* | *::*)
        fail "Slim plugin version is invalid for OpenCode V2: $slim_version"
        ;;
    *)
        if [ "$slim_major" -lt 3 ] \
            || { [ "$slim_major" -eq 3 ] && [ "$slim_minor" -eq 0 ] && [ "$slim_patch" -lt 5 ]; }; then
            fail "oh-my-opencode-slim $slim_version is V1-only; OpenCode V2 requires 3.0.5+ (run task ai.upgrade, then apply Home Manager)"
        else
            ok "oh-my-opencode-slim@$slim_version is on the V2-compatible release line"
        fi
        ;;
esac

open_code_cli() {
    npm exec --yes --package=@opencode/cli@2.2.0 -- opencode2 "$@"
}

read_v2_config() {
    config_home=$1
    (
        unset OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG_DIR
        XDG_CONFIG_HOME="$config_home" \
            OPENCODE_DISABLE_PROJECT_CONFIG=1 \
            open_code_cli api get /api/config --standalone
    )
}

read_v2_agents() {
    config_home=$1
    (
        unset OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG_DIR
        XDG_CONFIG_HOME="$config_home" \
            OPENCODE_DISABLE_PROJECT_CONFIG=1 \
            OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
            OPENCODE_DISABLE_CLAUDE_CODE=1 \
            open_code_cli api get /api/agent --standalone
    )
}

read_v2_skills() {
    config_home=$1
    (
        unset OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG_DIR
        XDG_CONFIG_HOME="$config_home" \
            OPENCODE_DISABLE_PROJECT_CONFIG=1 \
            open_code_cli api get /api/skill --standalone
    )
}

check_cli_config() {
    profile_name=$1
    cli_config=$2
    expect_todo_plugin=$3
    if [ ! -f "$cli_config" ]; then
        fail "OpenCode $profile_name cli.json is missing: $cli_config"
    elif jq -e '
        .["$schema"] == "https://opencode.ai/v2/cli.json"
        and .theme.name == "catppuccin-mocha-mauve"
        and (.plugins | index("./herdr-opencode") != null)
    ' "$cli_config" >/dev/null; then
        if [ "$expect_todo_plugin" = 1 ] \
            && ! jq -e '.plugins | index("./tui-plugins/todo") != null' "$cli_config" >/dev/null; then
            fail "OpenCode $profile_name cli.json does not load the shared Todo TUI plugin"
        else
            ok "OpenCode $profile_name cli.json uses the V2 theme settings"
        fi
    else
        fail "OpenCode $profile_name cli.json is missing its V2 schema or theme"
    fi
}

check_config_model() {
    profile_name=$1
    config=$2
    provider=$3
    model=$4
    if printf '%s\n' "$config" | jq -e --arg provider "$provider" --arg model "$model" '
        type == "array"
        and [ .[] | select(.type == "document") | .info.model? |
            select(.providerID == $provider and .model == $model) ] | length > 0
    ' >/dev/null; then
        ok "OpenCode $profile_name resolves the expected V2 model"
    else
        fail "OpenCode $profile_name does not resolve $provider/$model from V2 config entries"
    fi
}

check_config_plugin() {
    profile_name=$1
    config=$2
    plugin_spec=$3
    if printf '%s\n' "$config" | jq -e --arg spec "$plugin_spec" '
        type == "array"
        and [ .[] | select(.type == "document") | .info.plugins[]? |
            select(. == $spec) ] | length > 0
    ' >/dev/null; then
        ok "OpenCode resolves the pinned $profile_name plugin from V2 config entries"
    else
        fail "OpenCode V2 config entries do not contain $plugin_spec"
    fi
}

check_config_plugin_absent() {
    profile_name=$1
    config=$2
    plugin_spec=$3
    if printf '%s\n' "$config" | jq -e --arg spec "$plugin_spec" '
        type == "array"
        and [ .[] | select(.type == "document") | .info.plugins[]? |
            select(. == $spec) ] | length == 0
    ' >/dev/null; then
        ok "OpenCode $profile_name omits the V2-incompatible $plugin_spec plugin"
    else
        fail "OpenCode $profile_name still configures the V2-incompatible $plugin_spec plugin"
    fi
}

check_v2_worker_title_source() {
    profile_name=$1
    plugin_path=$2
    source="$repo_root/home/files/config/opencode/plugins/herdr-worker-title.js"
    if [ -f "$plugin_path" ] \
        && [ "$plugin_path" -ef "$source" ] \
        && grep -Fq 'import { Plugin } from "@opencode/plugin"' "$source" \
        && grep -Fq 'id: "dotfiles.herdr-worker-title"' "$source" \
        && grep -Fq 'ctx.event.subscribe' "$source"; then
        ok "OpenCode $profile_name links the V2 Herdr worker-title implementation"
    else
        fail "OpenCode $profile_name V2 Herdr worker-title source is missing or not linked"
    fi
}

check_cli_config Default "$default_cli_config" 1
check_cli_config Chat "$chat_config_home/opencode/cli.json" 0
check_cli_config OmO "$omo_config_home/opencode/cli.json" 1
check_cli_config Slim "$slim_config_home/opencode/cli.json" 1

if default_config=$(read_v2_config "$default_config_home" 2>/dev/null); then
    if printf '%s\n' "$default_config" | jq -e '
        type == "array"
        and [ .[] | select(.type == "document") | .info.plugins[]? |
            select(test("oh-my-openagent|oh-my-opencode-slim")) ] | length == 0
    ' >/dev/null; then
        ok 'the default OpenCode profile stays framework-plugin-free'
    else
        fail 'the default OpenCode V2 config contains a framework plugin reference'
    fi
    check_config_model Default "$default_config" openai gpt-6-sol
else
    fail 'OpenCode V2 could not resolve the default Config.Entry[] API'
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

check_profile_config() {
    profile_name=$1
    profile_config_home=$2
    expected_provider=$3
    expected_model=$4
    plugin_spec=${5:-}

    if profile_config=$(read_v2_config "$profile_config_home" 2>/dev/null); then
        check_config_model "$profile_name" "$profile_config" "$expected_provider" "$expected_model"
        if [ -n "$plugin_spec" ]; then
            check_config_plugin "$profile_name" "$profile_config" "$plugin_spec"
        fi
        if [ "$profile_name" != OmO ]; then
            profile_root="$profile_config_home/opencode"
            if [ -f "$profile_root/plugins/profile-shell-env/index.js" ]; then
                ok "OpenCode $profile_name profile shell environment source is present"
            else
                fail "OpenCode $profile_name profile shell environment source is missing"
            fi
        fi
    else
        fail "OpenCode could not resolve the $profile_name Config.Entry[] API"
    fi
}

check_profile_config Chat "$chat_config_home" openai gpt-6-sol
check_profile_config OmO "$omo_config_home" openai gpt-6-sol
check_profile_config Slim "$slim_config_home" amazon-bedrock global.anthropic.claude-opus-5 "$slim_plugin_spec"
check_v2_worker_title_source Default "$HOME/.config/opencode/plugins/herdr-worker-title/index.js"
check_v2_worker_title_source Chat "$chat_config_home/opencode/plugins/herdr-worker-title/index.js"
check_v2_worker_title_source Slim "$slim_config_home/opencode/plugins/herdr-worker-title/index.js"
warn 'V2 server plugin activation is not checked through /api/plugin because startup inventory is asynchronous; inspect plugin state after OpenCode starts'

if omo_config_entries=$(read_v2_config "$omo_config_home" 2>/dev/null); then
    check_config_plugin_absent OmO "$omo_config_entries" "$omo_plugin_spec"
else
    fail 'OpenCode could not resolve the OmO Config.Entry[] API'
fi
warn 'OmO is intentionally disabled by opencode-profile on V2 until a non-stub V2 plugin implementation is verified'

if chat_config=$(read_v2_config "$chat_config_home" 2>/dev/null); then
    if printf '%s\n' "$chat_config" | jq -e '
        type == "array"
        and [ .[] | select(.type == "document") | .info.default_agent? |
            select(. == "chat") ] | length > 0
    ' >/dev/null; then
        ok 'OpenCode Chat profile selects the V2 chat agent ID'
    else
        fail 'OpenCode Chat profile does not select the V2 chat agent ID'
    fi
    if chat_agents=$(read_v2_agents "$chat_config_home" 2>/dev/null) \
        && printf '%s\n' "$chat_agents" | jq -e '
            [.data[] | select(.mode == "primary" and .hidden != true) | .id]
            | length == 1 and .[0] == "chat"
        ' >/dev/null; then
        ok 'OpenCode Chat exposes only its primary agent through the V2 API'
    else
        fail 'OpenCode Chat agent isolation is incomplete in the V2 API'
    fi
else
    fail 'OpenCode could not resolve the Chat Config.Entry[] API'
fi

if jq -e '
    .keybinds["agent.list"] == "none"
    and .keybinds["agent.cycle"] == "none"
    and .keybinds["agent.cycle.reverse"] == "none"
' "$chat_config_home/opencode/cli.json" >/dev/null; then
    ok 'OpenCode Chat cli.json disables V2 agent switching'
else
    fail 'OpenCode Chat cli.json still allows V2 agent switching'
fi

if default_agents=$(read_v2_agents "$default_config_home" 2>/dev/null) \
    && printf '%s\n' "$default_agents" | jq -e '[.data[] | select(.id == "chat")] | length == 0' >/dev/null; then
    ok 'the default OpenCode profile does not expose Chat through the V2 API'
else
    fail 'the default OpenCode profile exposes Chat through the V2 API'
fi

herdr_worker_title_plugin="$repo_root/home/files/config/opencode/plugins/herdr-worker-title.js"
if [ -f "$herdr_worker_title_plugin" ] \
    && grep -Fq 'process.env.HERDR_AGENT_LAYOUT_WORKER === "1"' "$herdr_worker_title_plugin" \
    && grep -Fq 'delete event.env[variable]' "$herdr_worker_title_plugin"; then
    fail 'OpenCode V2 direct Herdr Supervisor shells lose HERDR_*; --standalone does not make this shared hook session-aware'
fi

if command -v happier >/dev/null 2>&1; then
    happier_version=$(happier --version 2>/dev/null || true)
    case "$happier_version" in
        *0.2.12*) fail "Happier $happier_version cannot start OpenCode V2 sessions" ;;
        *) warn 'Happier V2 server compatibility was not live-tested; use a V2-compatible Happier CLI build' ;;
    esac
else
    warn 'Happier is not installed; Happier worker startup was not tested'
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

herdr_tui_source="$HOME/.config/opencode/herdr-opencode/tui.js"
herdr_tui_shared="$HOME/.config/opencode/herdr-tui-session.js"
if [ -f "$herdr_tui_source" ] && [ -f "$herdr_tui_shared" ]; then
    ok 'Herdr V2 TUI plugin entrypoints are installed'
    for profile in chat omo slim; do
        profile_root="$HOME/.config/opencode-profiles/$profile/opencode"
        if [ -e "$profile_root/herdr-opencode/tui.js" ] \
            && [ "$profile_root/herdr-opencode/tui.js" -ef "$herdr_tui_source" \
            ] && [ -e "$profile_root/herdr-tui-session.js" \
            ] && [ "$profile_root/herdr-tui-session.js" -ef "$herdr_tui_shared" ]; then
            ok "OpenCode $profile profile links Herdr V2 TUI entrypoints"
        else
            fail "OpenCode $profile profile does not link the Herdr V2 TUI entrypoints"
        fi
    done
else
    fail 'Herdr V2 TUI plugin entrypoints are missing; run herdr integration install opencode'
fi

integration_source="$HOME/.config/opencode/plugins/herdr-agent-state.js"
if [ -f "$integration_source" ]; then
    ok "Herdr OpenCode integration exists"
    for profile in chat omo slim; do
        profile_integration="$HOME/.config/opencode-profiles/$profile/opencode/plugins/herdr-agent-state/index.js"
        if [ -e "$profile_integration" ] && [ "$profile_integration" -ef "$integration_source" ]; then
            ok "OpenCode $profile profile links the Herdr integration"
        else
            fail "OpenCode $profile profile does not link $integration_source"
        fi
    done
else
    fail "Herdr OpenCode integration is missing: $integration_source"
    for profile in chat omo slim; do
        profile_integration="$HOME/.config/opencode-profiles/$profile/opencode/plugins/herdr-agent-state/index.js"
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
if skills=$(read_v2_skills "$default_config_home" 2>/dev/null) \
    && printf '%s\n' "$skills" \
        | jq -e '[.data[] | select(.name == "herdr-agent-layout")] | length == 1' >/dev/null; then
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
