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
    require_brewfile_entry 'brew "opencode"'
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

omo_plugin_config="$repo_root/home/files/config/opencode/profiles/omo/opencode.jsonc"
omo_tui_config="$repo_root/home/files/config/opencode/profiles/omo/tui.json"
slim_plugin_config="$repo_root/home/files/config/opencode/profiles/slim/opencode.jsonc"
slim_tui_config="$repo_root/home/files/config/opencode/profiles/slim/tui.json"
default_plugin_config="$repo_root/home/files/config/opencode/opencode.jsonc"
default_tui_config="$repo_root/home/files/config/opencode/tui.json"
omo_config="$repo_root/home/files/omo/omo.jsonc"

omo_plugin_spec=$(sed -n 's/.*"\(oh-my-openagent@[^"]*\)".*/\1/p' "$omo_plugin_config" | head -n 1)
omo_tui_plugin_spec=$(sed -n 's/.*"\(oh-my-openagent@[^"]*\)".*/\1/p' "$omo_tui_config" | head -n 1)
case "$omo_plugin_spec" in
    oh-my-openagent@*)
        omo_version=${omo_plugin_spec#oh-my-openagent@}
        if printf '%s\n' "$omo_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)*$'; then
            ok "OpenCode pins $omo_plugin_spec"
        else
            fail "OpenCode OmO plugin pin is not an exact version: $omo_plugin_spec"
        fi
        ;;
    *)
        omo_version=
        fail 'OpenCode does not use an exact oh-my-openagent pin'
        ;;
esac

if [ -n "$omo_plugin_spec" ] && [ "$omo_tui_plugin_spec" = "$omo_plugin_spec" ]; then
    ok "OmO profile tui.json uses the same $omo_plugin_spec pin"
else
    fail "OmO profile tui.json pin does not match OmO profile opencode.jsonc ($omo_tui_plugin_spec != $omo_plugin_spec)"
fi

slim_plugin_spec=$(sed -n 's/.*"\(oh-my-opencode-slim@[^"]*\)".*/\1/p' "$slim_plugin_config" | head -n 1)
slim_tui_plugin_spec=$(sed -n 's/.*"\(oh-my-opencode-slim@[^"]*\)".*/\1/p' "$slim_tui_config" | head -n 1)
case "$slim_plugin_spec" in
    oh-my-opencode-slim@*)
        slim_version=${slim_plugin_spec#oh-my-opencode-slim@}
        if printf '%s\n' "$slim_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)*$'; then
            ok "OpenCode pins $slim_plugin_spec"
        else
            fail "OpenCode Slim plugin pin is not an exact version: $slim_plugin_spec"
        fi
        ;;
    *)
        slim_version=
        fail 'OpenCode does not use an exact oh-my-opencode-slim pin'
        ;;
esac

if [ -n "$slim_plugin_spec" ] && [ "$slim_tui_plugin_spec" = "$slim_plugin_spec" ]; then
    ok "Slim profile tui.json uses the same $slim_plugin_spec pin"
else
    fail "Slim profile tui.json pin does not match Slim profile opencode.jsonc ($slim_tui_plugin_spec != $slim_plugin_spec)"
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

check_npm_plugin_version oh-my-openagent "$omo_version"
check_npm_plugin_version oh-my-opencode-slim "$slim_version"

default_root_clean=true
for config in "$default_plugin_config" "$default_tui_config"; do
    if grep -Fq 'oh-my-openagent' "$config" || grep -Fq 'oh-my-opencode-slim' "$config"; then
        default_root_clean=false
    fi
done
if [ "$default_root_clean" = true ]; then
    ok "the default OpenCode config root stays framework-plugin-free"
else
    fail "the default OpenCode config root contains a framework plugin reference"
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
    config_file=$2
    plugin_spec=$3
    if resolved_config=$(OPENCODE_CONFIG="$config_file" opencode debug config --pure 2>/dev/null); then
        resolved_plugin=$(printf '%s\n' "$resolved_config" | jq -r --arg spec "$plugin_spec" '.plugin[]? | select(. == $spec)' | head -n 1)
        if [ "$resolved_plugin" = "$plugin_spec" ]; then
            ok "OpenCode resolves the pinned $profile_name plugin config"
        else
            fail "OpenCode resolved $profile_name config does not contain $plugin_spec"
        fi
    else
        fail "OpenCode could not resolve $config_file"
    fi
}

if command -v opencode >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    check_resolved_plugin_config OmO "$omo_plugin_config" "$omo_plugin_spec"
    check_resolved_plugin_config Slim "$slim_plugin_config" "$slim_plugin_spec"
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
    for profile in omo slim; do
        profile_integration="$HOME/.config/opencode-profiles/$profile/opencode/plugins/herdr-agent-state.js"
        if [ -e "$profile_integration" ] && [ "$profile_integration" -ef "$integration_source" ]; then
            ok "OpenCode $profile profile links the Herdr integration"
        else
            fail "OpenCode $profile profile does not link $integration_source"
        fi
    done
else
    fail "Herdr OpenCode integration is missing: $integration_source"
fi

if [ "$failures" -ne 0 ]; then
    printf 'AI stack check failed with %s error(s).\n' "$failures" >&2
    exit 1
fi

printf 'AI stack check passed.\n'
