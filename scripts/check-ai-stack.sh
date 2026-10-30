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

if command -v herdr >/dev/null 2>&1; then
    herdr_path=$(command -v herdr)
    managed_herdr="$HOME/.nix-profile/bin/herdr"
    if [ -x "$managed_herdr" ] && [ "$herdr_path" -ef "$managed_herdr" ]; then
        ok "Herdr resolves to the Home Manager package: $herdr_path"
    else
        fail "Herdr does not resolve to the Home Manager package: $herdr_path"
    fi
fi

if [ "$(uname -s)" = Darwin ]; then
    require_brewfile_entry 'brew "anomalyco/tap/opencode-v2", trusted: true'
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
slim_version=$(jq -er '.slim' "$plugin_versions")
slim_plugin_spec="oh-my-opencode-slim@$slim_version"
default_config_home="$HOME/.config"
default_cli_config="$default_config_home/opencode/cli.json"
chat_config_home="$HOME/.config/opencode-profiles/chat"
herdr_config_home="$HOME/.config/opencode-profiles/herdr"
slim_config_home="$HOME/.config/opencode-profiles/slim"

if printf '%s\n' "$slim_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)*$'; then
    ok "OpenCode pins $slim_plugin_spec"
else
    fail "OpenCode Slim plugin pin is not an exact version: $slim_plugin_spec"
fi

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
    expect_herdr_plugin=$4
    if [ ! -f "$cli_config" ]; then
        fail "OpenCode $profile_name cli.json is missing: $cli_config"
    elif jq -e \
        --argjson expect_todo "$expect_todo_plugin" \
        --argjson expect_herdr "$expect_herdr_plugin" '
        .["$schema"] == "https://opencode.ai/v2/cli.json"
        and .theme.name == "catppuccin-mocha-mauve"
        and ((((.plugins // []) | index("./tui-plugins/todo")) != null) == ($expect_todo == 1))
        and ((((.plugins // []) | index("./herdr-opencode")) != null) == ($expect_herdr == 1))
    ' "$cli_config" >/dev/null; then
        ok "OpenCode $profile_name cli.json uses the declared V2 TUI plugins"
    else
        fail "OpenCode $profile_name cli.json has unexpected V2 theme or plugin declarations"
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

check_config_share() {
    profile_name=$1
    config=$2
    if printf '%s\n' "$config" | jq -e '
        [.[] | select(.type == "document") | .info.share? | select(. == "disabled")] | length > 0
    ' >/dev/null; then
        ok "OpenCode $profile_name disables session sharing"
    else
        fail "OpenCode $profile_name does not disable session sharing"
    fi
}

check_v2_herdr_shell_source() {
    profile_name=$1
    plugin_path=$2
    source="$repo_root/home/files/config/opencode/plugins/herdr-shell-env.js"
    if [ -f "$plugin_path" ] \
        && [ "$plugin_path" -ef "$source" ] \
        && grep -Fq 'import { Plugin } from "@opencode/plugin"' "$source" \
        && grep -Fq 'id: "dotfiles.herdr-shell-env"' "$source" \
        && grep -Fq 'ctx.shell.hook' "$source"; then
        ok "OpenCode $profile_name links the V2 Herdr shell guard"
    else
        fail "OpenCode $profile_name V2 Herdr shell guard is missing or not linked"
    fi
}

check_cli_config Default "$default_cli_config" 1 0
check_cli_config Chat "$chat_config_home/opencode/cli.json" 0 0
check_cli_config Herdr "$herdr_config_home/opencode/cli.json" 1 1
check_cli_config Slim "$slim_config_home/opencode/cli.json" 1 0

if jq -e '
    .session.thinking == "show"
    and .session.grouping == "none"
    and .session.tps == true
    and .tabs.mode == "auto"
    and .tabs.indicators == "status"
    and .attention.notifications == true
    and .attention.sound == false
' "$herdr_config_home/opencode/cli.json" >/dev/null; then
    ok 'OpenCode Herdr uses native TUI thinking, TPS, and status indicators without sound'
else
    fail 'OpenCode Herdr cli.json is missing its native TUI status settings'
fi

for regular_profile_cli in \
    "$chat_config_home/opencode/cli.json" \
    "$slim_config_home/opencode/cli.json"; do
    if jq -e '
        .session.thinking == null
        and .session.grouping == null
        and .session.tps == null
    ' "$regular_profile_cli" >/dev/null; then
        ok "OpenCode profile keeps Herdr-only session display settings out of $regular_profile_cli"
    else
        fail "OpenCode profile forces Herdr-only session display settings in $regular_profile_cli"
    fi
done

if default_config=$(read_v2_config "$default_config_home" 2>/dev/null); then
    if printf '%s\n' "$default_config" | jq -e '
        type == "array"
        and [ .[] | select(.type == "document") | .info.plugins[]? |
            select(test("oh-my-opencode-slim")) ] | length == 0
    ' >/dev/null; then
        ok 'the default OpenCode profile stays framework-plugin-free'
    else
        fail 'the default OpenCode V2 config contains a framework plugin reference'
    fi
    check_config_model Default "$default_config" openai gpt-6-sol
    check_config_share Default "$default_config"
else
    fail 'OpenCode V2 could not resolve the default Config.Entry[] API'
fi

check_profile_config() {
    profile_name=$1
    profile_config_home=$2
    expected_provider=$3
    expected_model=$4
    plugin_spec=${5:-}

    if profile_config=$(read_v2_config "$profile_config_home" 2>/dev/null); then
        check_config_model "$profile_name" "$profile_config" "$expected_provider" "$expected_model"
        check_config_share "$profile_name" "$profile_config"
        if [ -n "$plugin_spec" ]; then
            check_config_plugin "$profile_name" "$profile_config" "$plugin_spec"
        fi
        profile_root="$profile_config_home/opencode"
        if [ -f "$profile_root/plugins/profile-shell-env/index.js" ]; then
            ok "OpenCode $profile_name profile shell environment source is present"
        else
            fail "OpenCode $profile_name profile shell environment source is missing"
        fi
    else
        fail "OpenCode could not resolve the $profile_name Config.Entry[] API"
    fi
}

check_profile_config Chat "$chat_config_home" openai gpt-6-sol
check_profile_config Herdr "$herdr_config_home" openai gpt-6-sol
check_profile_config Slim "$slim_config_home" amazon-bedrock global.anthropic.claude-opus-5 "$slim_plugin_spec"
check_v2_herdr_shell_source Default "$HOME/.config/opencode/plugins/herdr-shell-env/index.js"
check_v2_herdr_shell_source Slim "$slim_config_home/opencode/plugins/herdr-shell-env/index.js"
if [ ! -e "$herdr_config_home/opencode/plugins/herdr-shell-env/index.js" ]; then
    ok 'OpenCode Herdr profile does not scrub the pane environment needed by visible delegation'
else
    fail 'OpenCode Herdr profile still loads the incompatible shell environment scrubber'
fi
warn 'V2 server plugin activation is not checked through /api/plugin because startup inventory is asynchronous; inspect plugin state after OpenCode starts'

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

if grep -Fq 'DOTFILES_OPENCODE_HERDR_PRIVATE_CONFIG' "$repo_root/bin/opencode-profile" \
    && grep -Fq 'Herdr OpenCode V2 must use the managed private profile' "$repo_root/bin/opencode-v2" \
    && grep -Fq 'Herdr OpenCode V2 cannot use a shared server' "$repo_root/bin/opencode-v2"; then
    ok 'OpenCode V2 Herdr startup is limited to the managed private standalone profile'
else
    fail 'OpenCode V2 Herdr private-profile launch guard is missing'
fi
warn 'Herdr targeted prompt, route isolation, recovery, and scoped Ctrl-C passed isolated E2E; permission and reconnect remain unverified'

if command -v happier >/dev/null 2>&1; then
    happier_version=$(happier --version 2>/dev/null || true)
    warn "Happier personal OC2 sessions are optional (installed: ${happier_version:-unknown}); isolated CLI 0.2.17 could host a V2.2.0 TUI, but reattach failed pane_not_found and Stop did not terminate the test runner/managed server"
else
    warn 'Happier is not installed; Herdr workers do not depend on it'
fi

if command -v herdr >/dev/null 2>&1; then
    integration_status=$(herdr integration status)
    for target in claude codex; do
        status_line=$(printf '%s\n' "$integration_status" | grep "^${target}:" || true)
        case "$status_line" in
            "$target: current "*) ok "Herdr $status_line" ;;
            *) fail "Herdr integration is not current: ${status_line:-$target: missing}" ;;
        esac
    done
fi

herdr_profile_root="$herdr_config_home/opencode"
herdr_tui="$herdr_profile_root/herdr-opencode/tui.js"
herdr_tui_shared="$herdr_profile_root/herdr-tui-session.js"
herdr_server="$herdr_profile_root/plugins/herdr-agent-state/index.js"
if [ -L "$herdr_tui" ] \
    && [ -L "$herdr_tui_shared" ] \
    && [ -L "$herdr_server" ] \
    && grep -Fq 'HERDR_INTEGRATION_ID=opencode-tui-v2' "$herdr_tui" \
    && grep -Fq '../herdr-tui-session.js' "$herdr_tui" \
    && grep -Fq 'HERDR_INTEGRATION_ID=opencode-tui' "$herdr_tui_shared" \
    && grep -Fq 'HERDR_INTEGRATION_ID=opencode' "$herdr_server"; then
    ok 'OpenCode Herdr profile links immutable Nix TUI and server plugin assets'
else
    fail 'OpenCode Herdr profile is missing immutable Nix TUI or server plugin assets'
fi

for legacy_herdr_path in \
    "$HOME/.config/opencode/plugins/herdr-agent-state.js" \
    "$HOME/.config/opencode/herdr-opencode" \
    "$HOME/.config/opencode/herdr-tui-session.js"; do
    if [ -e "$legacy_herdr_path" ] || [ -L "$legacy_herdr_path" ]; then
        fail "Mutable Herdr OpenCode integration still exists: $legacy_herdr_path"
    else
        ok "Mutable Herdr OpenCode integration is absent: $legacy_herdr_path"
    fi
done

for regular_profile in chat slim; do
    regular_profile_root="$HOME/.config/opencode-profiles/$regular_profile/opencode"
    if [ ! -e "$regular_profile_root/herdr-opencode" ] \
        && [ ! -e "$regular_profile_root/herdr-tui-session.js" ] \
        && [ ! -e "$regular_profile_root/plugins/herdr-agent-state/index.js" ]; then
        ok "OpenCode $regular_profile profile stays independent of Herdr runtime plugins"
    else
        fail "OpenCode $regular_profile profile still contains Herdr runtime plugins"
    fi
done

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
