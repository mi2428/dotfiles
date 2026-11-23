#!/bin/sh
set -eu

profiles=${1:?usage: ensure-opencode-services.sh PROFILE_CONFIG_ROOT}

for profile in herdr slim; do
    case "$profile" in
        herdr) port=4098 ;;
        slim) port=4099 ;;
    esac
    config="$profiles/$profile/opencode/service.json"
    # OpenCode adds its password here. Never replace a live service's writable config.
    if [ ! -e "$config" ] && [ ! -L "$config" ]; then
        mkdir -p "$(dirname "$config")"
        (
            umask 077
            set -C
            printf '{"hostname":"127.0.0.1","port":%s}\n' "$port" > "$config"
        )
    fi
    if ! jq -e --argjson port "$port" '.port == $port' "$config" >/dev/null; then
        printf 'OpenCode %s service config is invalid or its port is not %s; existing settings were left unchanged: %s\n' \
            "$profile" "$port" "$config" >&2
        exit 78
    fi
done
