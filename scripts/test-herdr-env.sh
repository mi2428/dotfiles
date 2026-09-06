#!/bin/sh

set -eu

DOTFILES_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
FISH=$(command -v fish)
FAKE_BIN=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN"' EXIT

cat >"$FAKE_BIN/ps" <<'EOF'
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
chmod +x "$FAKE_BIN/ps"

env \
  PATH="$FAKE_BIN:$PATH" \
  HERDR_ENV=1 \
  HERDR_SOCKET_PATH=/tmp/stale.sock \
  HERDR_FUTURE_MARKER=stale \
  "$FISH" --no-config -c \
  "source '$DOTFILES_ROOT/home/files/config/fish/conf.d/10_general.fish'; not set -q HERDR_ENV; and not set -q HERDR_SOCKET_PATH; and not set -q HERDR_FUTURE_MARKER"

env \
  PATH="$FAKE_BIN:$PATH" \
  FAKE_PS_MODE=live \
  HERDR_ENV=1 \
  HERDR_SOCKET_PATH=/tmp/live.sock \
  HERDR_FUTURE_MARKER=live \
  "$FISH" --no-config -c \
  "source '$DOTFILES_ROOT/home/files/config/fish/conf.d/10_general.fish'; test \"\$HERDR_ENV\" = 1; and test \"\$HERDR_SOCKET_PATH\" = /tmp/live.sock; and test \"\$HERDR_FUTURE_MARKER\" = live"

printf '%s\n' 'Herdr environment tests: ok'

FAKE_HOME="$FAKE_BIN/home"
mkdir -p "$FAKE_HOME"
cat >"$FAKE_BIN/happier" <<'EOF'
#!/bin/sh

printf 'backend=%s\n' "$HAPPIER_OPENCODE_BACKEND_MODE"
printf 'worker=%s\n' "$HERDR_HAPPIER_WORKER"
printf 'parent_session=%s\n' "${HAPPIER_SESSION_ID-<unset>}"
printf 'state=%s\n' "${HAPPIER_OPENCODE_SERVER_STATE_PATH-<unset>}"
printf 'server_url=%s\n' "${HAPPIER_OPENCODE_SERVER_URL-<unset>}"
printf 'config=%s\n' "$OPENCODE_CONFIG_CONTENT"
printf 'args'
for arg in "$@"; do
  printf '|%s' "$arg"
done
printf '\n'
EOF
chmod +x "$FAKE_BIN/happier"

worker_output=$(
  env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$FAKE_HOME" \
    HERDR_AGENT_LAYOUT_WORKER=1 \
    HERDR_HAPPIER_PARENT_SESSION_ID=parent_123 \
    HERDR_HAPPIER_WORKER_NAME=verify-worker \
    HAPPIER_SESSION_ID=parent_should_not_leak \
    HAPPIER_OPENCODE_SERVER_STATE_PATH=/tmp/parent-state.json \
    HAPPIER_OPENCODE_SERVER_URL=http://127.0.0.1:1234 \
    "$DOTFILES_ROOT/bin/happier-opencode-worker" \
      --agent-mode 'Herdr Worker' \
      --model openai/gpt-test
)

assert_worker_output() {
  case "$worker_output" in
    *"$1"*) return ;;
    *)
    printf '%s\n' 'Happier OpenCode worker wrapper test failed' >&2
    printf 'missing: %s\n' "$1" >&2
    printf '%s\n' "$worker_output" >&2
    exit 1
    ;;
  esac
}

assert_worker_output 'backend=server'
assert_worker_output 'worker=1'
assert_worker_output 'parent_session=<unset>'
assert_worker_output 'state=<unset>'
assert_worker_output 'server_url=<unset>'
assert_worker_output "config={\"\$schema\":\"https://opencode.ai/config.json#herdr-parent_123-verify-worker\",\"default_agent\":\"Herdr Worker\",\"model\":\"openai/gpt-test\"}"
assert_worker_output 'args|opencode|--permission-mode|yolo|--agent-mode|Herdr Worker|--model|openai/gpt-test'

if env \
  PATH="$FAKE_BIN:$PATH" \
  HOME="$FAKE_HOME" \
  HERDR_AGENT_LAYOUT_WORKER=1 \
  HERDR_HAPPIER_WORKER_NAME=verify-worker \
  "$DOTFILES_ROOT/bin/happier-opencode-worker" \
    --agent-mode 'Herdr Worker' \
    --model openai/gpt-test >/dev/null 2>&1; then
  printf '%s\n' 'Happier OpenCode worker wrapper accepted a missing parent session' >&2
  exit 1
fi

printf '%s\n' 'Happier OpenCode worker tests: ok'
