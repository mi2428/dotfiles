#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fish=$(command -v fish)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/herdr-env.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
bin=$scratch/bin
mkdir -p "$bin" "$scratch/scripts" "$scratch/profiles/herdr/opencode" "$scratch/profiles/chat/opencode"

cat >"$bin/ps" <<'EOF'
#!/bin/sh
pid=
field=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p) pid=$2; shift 2 ;;
        -o) field=$2; shift 2 ;;
        *) shift ;;
    esac
done
case "$field" in
    ppid=)
        case "${FAKE_PS_MODE:-stale}:$pid" in
            live:42 | stale:43) printf '%s\n' 1 ;;
            stale:42) printf '%s\n' 43 ;;
            *) printf '%s\n' 42 ;;
        esac
        ;;
    comm=)
        case "${FAKE_PS_MODE:-stale}:$pid" in
            live:42 | stale:43) printf '%s\n' /opt/homebrew/bin/herdr ;;
            *) printf '%s\n' /Applications/Ghostty.app/Contents/MacOS/ghostty ;;
        esac
        ;;
esac
EOF
cat >"$bin/opencode" <<'EOF'
#!/bin/sh
printf 'xdg=%s\n' "$XDG_CONFIG_HOME"
printf 'content=%s\n' "${OPENCODE_CONFIG_CONTENT-<unset>}"
printf 'args'
for arg do printf '|%s' "$arg"; done
printf '\n'
EOF
chmod +x "$bin/ps" "$bin/opencode"
ln -s "$root/bin/opencode-profile" "$bin/opencode-profile"
ln -s "$root/scripts/opencode-profile.sh" "$scratch/scripts/opencode-profile.sh"

env PATH="$bin:$PATH" HERDR_ENV=1 HERDR_SOCKET_PATH=/tmp/stale.sock \
    "$fish" --no-config -c \
    "source '$root/home/files/config/fish/conf.d/10_general.fish'; not set -q HERDR_ENV; and not set -q HERDR_SOCKET_PATH"
env PATH="$bin:$PATH" FAKE_PS_MODE=live HERDR_ENV=1 HERDR_SOCKET_PATH=/tmp/live.sock \
    "$fish" --no-config -c \
    "source '$root/home/files/config/fish/conf.d/10_general.fish'; test \"\$HERDR_ENV\" = 1; and test \"\$HERDR_SOCKET_PATH\" = /tmp/live.sock"

herdr_config=$scratch/profiles/herdr
printf '%s\n' '{}' >"$herdr_config/opencode/opencode.jsonc"
printf '%s\n' '{}' >"$herdr_config/opencode/cli.json"
printf '%s\n' '{}' >"$scratch/profiles/chat/opencode/opencode.jsonc"

output=$(env PATH="$bin:$PATH" HOME="$scratch/home" OPENCODE_PROFILE_CONFIG_HOME="$herdr_config" \
    HERDR_ENV=1 "$fish" --no-config -c \
    "source '$root/home/files/config/fish/conf.d/20_aliases.fish'; oc++ --prompt test")
case "$output" in
    *"xdg=$herdr_config"*'"default_agent":"herdr-supervisor"'*'args|--standalone|--auto|--prompt|test'*) ;;
    *) printf '%s\n' 'Herdr supervisor did not start a private profile' >&2; exit 1 ;;
esac

output=$(env PATH="$bin:$PATH" HOME="$scratch/home" OPENCODE_PROFILE_CONFIG_HOME="$herdr_config" \
    HERDR_ENV=1 HERDR_AGENT_LAYOUT_WORKER=1 HERDR_OPENCODE_MODEL=openai/gpt-test \
    "$bin/opencode-profile" herdr --prompt test)
case "$output" in
    *'"default_agent":"herdr-worker"'*'"model":"openai/gpt-test"'*'args|--standalone|--prompt|test'*) ;;
    *) printf '%s\n' 'Herdr worker did not start a private profile' >&2; exit 1 ;;
esac

if env PATH="$bin:$PATH" HOME="$scratch/home" OPENCODE_PROFILE_CONFIG_HOME="$herdr_config" \
    HERDR_ENV=1 HERDR_AGENT_LAYOUT_WORKER=1 "$bin/opencode-profile" herdr >/dev/null 2>&1; then
    printf '%s\n' 'Herdr worker started without a model' >&2; exit 1
fi
for arg in --server=http://127.0.0.1:4096 --attach=http://127.0.0.1:4096; do
    if env PATH="$bin:$PATH" HOME="$scratch/home" OPENCODE_PROFILE_CONFIG_HOME="$herdr_config" \
        HERDR_ENV=1 "$bin/opencode-profile" herdr "$arg" >/dev/null 2>&1; then
        printf '%s\n' 'Herdr accepted a shared server' >&2; exit 1
    fi
done
if env PATH="$bin:$PATH" HOME="$scratch/home" OPENCODE_PROFILE_CONFIG_HOME="$scratch/profiles/chat" \
    HERDR_ENV=1 "$bin/opencode-profile" chat >/dev/null 2>&1; then
    printf '%s\n' 'Herdr accepted a non-private profile' >&2; exit 1
fi
if env PATH="$bin:$PATH" HOME="$scratch/home" OPENCODE_PROFILE_CONFIG_HOME="$herdr_config" \
    HERDR_ENV=0 "$bin/opencode-profile" herdr >/dev/null 2>&1; then
    printf '%s\n' 'Herdr profile started outside Herdr' >&2; exit 1
fi
if env PATH="$bin:$PATH" HOME="$scratch/home" DOTFILES_REPO_ROOT="$root" HERDR_ENV=1 \
    "$root/bin/opencode.dev" >/dev/null 2>&1; then
    printf '%s\n' 'OpenCode dev launcher bypassed the Herdr profile' >&2; exit 1
fi

printf '%s\n' 'Herdr profile launch and isolation: ok'
