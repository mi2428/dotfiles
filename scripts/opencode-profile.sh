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
    printf '%s\n' 'opencode-profile: use the Herdr profile inside a Herdr pane' >&2
    exit 69
fi
if [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HC_TERMINAL_ID:-}" ]; then
    printf '%s\n' 'opencode-profile: Herdr and hc terminal identities cannot be combined' >&2
    exit 69
fi
if [ "$profile" = hc ]; then
    if [ "${HERDR_ENV:-}" = 1 ] || [ -z "${HC_TERMINAL_ID:-}" ] || ! command -v hc >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        printf '%s\n' 'opencode-profile: hc requires a live herdr-core terminal, not a Herdr pane' >&2
        exit 69
    fi
    terminal=$(hc get --json "$HC_TERMINAL_ID") || exit 69
    printf '%s\n' "$terminal" | jq -e '
        .state == "live" and .labels["herdr.space"] != null and .labels["herdr.tab"] != null' >/dev/null || {
        printf '%s\n' 'opencode-profile: hc terminal is not displayed in Herdr App' >&2
        exit 69
    }
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
fi
if [ "$profile" = slim ]; then
    # Slim's background orchestration is an OpenCode experimental feature.
    export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
fi

use_standalone=true
explicit_server=false
explicit_standalone=false
for arg; do
    case "$arg" in
        --server | --server=* | --attach | --attach=*)
            use_standalone=false
            explicit_server=true
            ;;
        --standalone)
            explicit_standalone=true
            ;;
    esac
done

# Native child views join their parent's shared service; no independent worker server is started.
if [ "$profile" = herdr ] || [ "$profile" = hc ]; then
    export HERDR_APP_HOME="${HERDR_APP_HOME:-"$caller_config_home/herdr-app"}"
    if [ "$explicit_standalone" = false ] && [ "$explicit_server" = false ]; then
        use_standalone=false
    fi
fi
if [ "$profile" = herdr ]; then
    export XDG_STATE_HOME="${OPENCODE_HERDR_STATE_HOME:-"${HOME:?}/.local/state/opencode-profiles/herdr"}"
fi

if [ "$profile" = slim ]; then
    # Keep the Slim background service registration separate from the default
    # profile. The matching port lives in the profile's opencode/service.json.
    export XDG_STATE_HOME="${OPENCODE_SLIM_STATE_HOME:-"${HOME:?}/.local/state/opencode-profiles/slim"}"
    if [ "$explicit_standalone" = false ] && [ "$explicit_server" = false ] &&
        [ -n "${HC_TERMINAL_ID:-}" ] && [ ! -f "$profile_config/service.json" ]; then
        printf 'opencode-profile: Slim service config is missing; run Home Manager activation\n' >&2
        exit 78
    fi
fi

# Herdr Desktop spawns child panes only for the v2 shared service, not for
# --server. Running without --standalone uses the profile-local service, while
# HERDR_APP_HOME keeps herdr-app on the app's own config after the XDG override.
if [ "$profile" = slim ] && [ -n "${HC_TERMINAL_ID:-}" ] && [ "$explicit_standalone" = false ]; then
    export HERDR_APP_HOME="${HERDR_APP_HOME:-"$caller_config_home/herdr-app"}"
    use_standalone=false
fi

if [ "$use_standalone" = true ] && [ "$explicit_standalone" = false ]; then
    exec opencode --standalone "$@"
fi
exec opencode "$@"
