#!/bin/sh
set -eu

profile=${1:-}
if [ -z "$profile" ]; then
    printf '%s\n' 'usage: opencode-profile {chat|herdr|slim} [opencode options...]' >&2
    exit 64
fi
shift

case "$profile" in
    chat | herdr | slim)
        ;;
    *)
        printf 'opencode-profile: unknown profile: %s\n' "$profile" >&2
        exit 64
        ;;
esac

caller_config_home=${XDG_CONFIG_HOME:-"${HOME:?}/.config"}
profile_config_home=${OPENCODE_PROFILE_CONFIG_HOME:-"${HOME:?}/.config/opencode-profiles/$profile"}
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
            herdr_model=${HERDR_OPENCODE_MODEL:-openai/gpt-6-sol}
            ;;
        *)
            printf '%s\n' 'opencode-profile: invalid HERDR_AGENT_LAYOUT_WORKER value' >&2
            exit 64
            ;;
    esac
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
    herdr_config=$(jq -cn \
        --arg agent "$herdr_agent" \
        --arg model "$herdr_model" \
        '{"$schema":"https://opencode.ai/config.json",default_agent:$agent,model:$model}')
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
if [ "$profile" = herdr ]; then
    unset OPENCODE_CLI_CONFIG_CONTENT
    export OPENCODE_CONFIG_CONTENT="$herdr_config"
fi
if [ "$profile" = slim ]; then
    # Slim's background orchestration is an OpenCode experimental feature.
    export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
fi

use_standalone=true
for arg; do
    case "$arg" in
        --server | --server=* | --attach | --attach=*)
            if [ "$profile" = herdr ]; then
                printf '%s\n' 'opencode-profile: Herdr sessions cannot attach to a shared server' >&2
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
