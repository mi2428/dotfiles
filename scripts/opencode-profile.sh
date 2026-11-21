#!/bin/sh
set -eu

profile=${1:-}
if [ -z "$profile" ]; then
    printf '%s\n' 'usage: opencode-profile {chat|hc|herdr|slim} [opencode options...]' >&2
    exit 64
fi
shift

case "$profile" in
    chat | hc | herdr | slim)
        ;;
    *)
        printf 'opencode-profile: unknown profile: %s\n' "$profile" >&2
        exit 64
        ;;
esac

caller_config_home=${XDG_CONFIG_HOME:-"${HOME:?}/.config"}
if [ "$profile" = hc ]; then
    profile_config_home=${OPENCODE_PROFILE_CONFIG_HOME:-"$caller_config_home"}
else
    profile_config_home=${OPENCODE_PROFILE_CONFIG_HOME:-"${HOME:?}/.config/opencode-profiles/$profile"}
fi
profile_config="$profile_config_home/opencode"
if [ ! -f "$profile_config/opencode.jsonc" ]; then
    printf 'opencode-profile: profile is not installed: %s\n' "$profile_config_home" >&2
    printf '%s\n' 'run the Home Manager activation, then retry' >&2
    exit 78
fi
if [ "${HERDR_ENV:-}" = 1 ] && [ "$profile" != herdr ]; then
    printf '%s\n' 'opencode-profile: Herdr sessions require the managed private profile' >&2
    exit 69
fi
if [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HC_TERMINAL_ID:-}" ]; then
    printf '%s\n' 'opencode-profile: Herdr and hc terminal identities cannot be combined' >&2
    exit 69
fi
if [ "$profile" = hc ]; then
    [ "${HERDR_ENV:-}" != 1 ] && [ -n "${HC_TERMINAL_ID:-}" ] && command -v hc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || {
        printf '%s\n' 'opencode-profile: hc requires a live herdr-core terminal, not a Herdr pane' >&2
        exit 69
    }
    terminal=$(hc get --json "$HC_TERMINAL_ID") || exit 69
    hc_agent=$(printf '%s\n' "$terminal" | jq -er '
        select(.state == "live" and .labels["herdr.space"] != null and .labels["herdr.tab"] != null)
        | if .parent == null then "herdr-supervisor"
          elif .labels["herdr.supervised"] == "1" then "herdr-worker"
          else empty end') || {
        printf '%s\n' 'opencode-profile: hc terminal is not an app supervisor or marked worker' >&2
        exit 69
    }
    case "${HC_OPENCODE_MODEL:-}" in
        '' | */*) ;;
        *) printf '%s\n' 'opencode-profile: HC_OPENCODE_MODEL must be provider/model' >&2; exit 64 ;;
    esac
    hc_config=$(jq -cn --arg agent "$hc_agent" --arg model "${HC_OPENCODE_MODEL:-}" \
        '{"$schema":"https://opencode.ai/config.json",default_agent:$agent} + (if $model == "" then {} else {model:$model} end)')
fi
if [ "$profile" = herdr ]; then
    [ "${HERDR_ENV:-}" = 1 ] || {
        printf '%s\n' 'opencode-profile: the Herdr profile requires a Herdr pane' >&2
        exit 69
    }
    [ -f "$profile_config/cli.json" ] || {
        printf 'opencode-profile: Herdr cli.json is missing: %s\n' "$profile_config" >&2
        exit 78
    }
    command -v jq >/dev/null 2>&1 || {
        printf '%s\n' 'opencode-profile: jq is required to build the private Herdr config' >&2
        exit 69
    }

    case "${HERDR_AGENT_LAYOUT_WORKER:-}" in
        1)
            herdr_agent=herdr-worker
            herdr_model=${HERDR_OPENCODE_MODEL:-}
            [ -n "$herdr_model" ] || {
                printf '%s\n' 'opencode-profile: a catalog-verified HERDR_OPENCODE_MODEL is required for workers' >&2
                exit 64
            }
            ;;
        '' | 0)
            herdr_agent=herdr-supervisor
            herdr_model=${HERDR_OPENCODE_MODEL:-}
            ;;
        *)
            printf '%s\n' 'opencode-profile: invalid HERDR_AGENT_LAYOUT_WORKER value' >&2
            exit 64
            ;;
    esac
    if [ -n "$herdr_model" ]; then
        case "$herdr_model" in
            */*)
                [ -n "${herdr_model%%/*}" ] && [ -n "${herdr_model#*/}" ] || {
                    printf 'opencode-profile: invalid Herdr model: %s\n' "$herdr_model" >&2
                    exit 64
                }
                ;;
            *)
                printf 'opencode-profile: expected HERDR_OPENCODE_MODEL=provider/model, got: %s\n' "$herdr_model" >&2
                exit 64
                ;;
        esac
    fi
    herdr_config=$(jq -cn \
        --arg agent "$herdr_agent" \
        --arg model "$herdr_model" \
        '{"$schema":"https://opencode.ai/config.json",default_agent:$agent} + (if $model == "" then {} else {model:$model} end)')
fi
if [ "$profile" = slim ]; then
    if ! command -v jq >/dev/null 2>&1; then
        printf '%s\n' 'opencode-profile: jq is required to verify the Slim V2 plugin pin' >&2
        exit 69
    fi
    if ! slim_plugin_spec=$(jq -er '[.plugins[]? | select(type == "string" and startswith("oh-my-opencode-slim@"))][0]' "$profile_config/opencode.jsonc"); then
        printf '%s\n' 'opencode-profile: the Slim V2 plugin pin is missing or invalid' >&2
        exit 69
    fi
    slim_version=${slim_plugin_spec#*@}
    slim_base=${slim_version%%[-+]*}
    slim_major=${slim_base%%.*}
    slim_rest=${slim_base#*.}
    slim_minor=${slim_rest%%.*}
    slim_patch=${slim_rest#*.}
    case "$slim_major:$slim_minor:$slim_patch" in
        *[!0-9:]* | :* | *::*)
            printf 'opencode-profile: invalid Slim plugin version: %s\n' "$slim_version" >&2
            exit 69
            ;;
    esac
    if [ "$slim_major" -lt 3 ] ||
        { [ "$slim_major" -eq 3 ] && [ "$slim_minor" -eq 0 ] && [ "$slim_patch" -lt 5 ]; }; then
        printf 'opencode-profile: oh-my-opencode-slim %s is V1-only; OpenCode V2 requires the verified 3.0.5+ line\n' "$slim_version" >&2
        printf '%s\n' 'update the pin, apply Home Manager, then retry' >&2
        exit 69
    fi
fi

export OPENCODE_CHILD_XDG_CONFIG_HOME="$caller_config_home"
export XDG_CONFIG_HOME="$profile_config_home"
# Do not let an externally supplied OpenCode config override the selected
# profile (the profile switch itself is the source of truth).
unset OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT OPENCODE_CONFIG_DIR
if [ "$profile" = herdr ] || [ "$profile" = hc ]; then
    unset OPENCODE_CLI_CONFIG_CONTENT
    if [ "$profile" = hc ]; then
        export OPENCODE_CONFIG_CONTENT="$hc_config"
    else
        export OPENCODE_CONFIG_CONTENT="$herdr_config"
    fi
fi
if [ "$profile" = slim ]; then
    # Slim's background orchestration is an OpenCode experimental feature.
    export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
fi

use_standalone=true
for arg; do
    case "$arg" in
        --server | --server=* | --attach | --attach=*)
            if [ "$profile" = herdr ] || [ "$profile" = hc ]; then
                printf '%s\n' 'opencode-profile: supervised sessions cannot attach to a shared server' >&2
                exit 64
            fi
            use_standalone=false
            ;;
    esac
done

if [ "$use_standalone" = true ]; then
    exec opencode --standalone "$@"
fi
exec opencode "$@"
