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

cat >"$FAKE_BIN/herdr" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FAKE_BIN/herdr"

cat >"$FAKE_BIN/opencode-v2" <<'EOF'
#!/bin/sh

printf 'xdg=%s\n' "$XDG_CONFIG_HOME"
printf 'content=%s\n' "${OPENCODE_CONFIG_CONTENT-<unset>}"
printf 'args'
for arg in "$@"; do
  printf '|%s' "$arg"
done
printf '\n'
EOF
chmod +x "$FAKE_BIN/opencode-v2"

cat >"$FAKE_BIN/opencode" <<'EOF'
#!/bin/sh

if [ "${1:-}" = --version ]; then
  printf 'opencode %s\n' "$FAKE_OPENCODE_VERSION"
  exit 0
fi
printf 'args'
for arg in "$@"; do
  printf '|%s' "$arg"
done
printf '\n'
EOF
chmod +x "$FAKE_BIN/opencode"

runtime_version=$(env PATH="$FAKE_BIN:$PATH" FAKE_OPENCODE_VERSION=v2.2.0 \
  "$DOTFILES_ROOT/bin/opencode-v2" --version)
case "$runtime_version" in
  'opencode v2.2.0') ;;
  *)
    printf 'OpenCode V2 launcher returned an unexpected version: %s\n' "$runtime_version" >&2
    exit 1
    ;;
esac

for unsupported_version in v2.1.3 v0.0.0-next-16722; do
  if env PATH="$FAKE_BIN:$PATH" FAKE_OPENCODE_VERSION="$unsupported_version" \
    "$DOTFILES_ROOT/bin/opencode-v2" --version >/dev/null 2>&1; then
    printf 'OpenCode V2 launcher accepted an unsupported version: %s\n' "$unsupported_version" >&2
    exit 1
  fi
done

if herdr_launch=$(env PATH="$FAKE_BIN:$PATH" FAKE_OPENCODE_VERSION=v2.2.0 HERDR_ENV=1 \
  "$DOTFILES_ROOT/bin/opencode-v2" --standalone --auto 2>&1); then
  printf '%s\n' 'OpenCode V2 launcher permitted unbound Herdr pane credentials' >&2
  exit 1
fi
case "$herdr_launch" in
  *'Herdr pane sessions require session-bound shell attribution'*) ;;
  *) printf 'OpenCode V2 launcher rejected Herdr with an unexpected error: %s\n' "$herdr_launch" >&2; exit 1 ;;
esac

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

assert_opencode_output() {
  case "$opencode_output" in
    *"$1"*) return ;;
    *)
      printf '%s\n' 'OpenCode V2 profile wrapper test failed' >&2
      printf 'missing: %s\n' "$1" >&2
      printf '%s\n' "$opencode_output" >&2
      exit 1
      ;;
  esac
}

opencode_output=$(
  env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$FAKE_BIN/home" \
    XDG_CONFIG_HOME="$FAKE_BIN/default-config" \
    OPENCODE_CONFIG_CONTENT='{"model":"openai/gpt-test"}' \
    HERDR_ENV=1 \
    "$FISH" --no-config -c \
      "source '$DOTFILES_ROOT/home/files/config/fish/conf.d/20_aliases.fish'; oc++ --prompt 'verify v2'"
)
assert_opencode_output "xdg=$FAKE_BIN/default-config"
assert_opencode_output '"default_agent":"herdr-supervisor"'
assert_opencode_output '"model":"openai/gpt-test"'
assert_opencode_output 'args|--standalone|--auto|--prompt|verify v2'
case "$opencode_output" in
  *'|--agent|'* | *'|--agent='*)
    printf '%s\n' 'OpenCode V2 TUI wrapper passed the unsupported --agent flag' >&2
    printf '%s\n' "$opencode_output" >&2
    exit 1
    ;;
esac

for profile in chat slim; do
  profile_config_home="$FAKE_BIN/profiles/$profile"
  mkdir -p "$profile_config_home/opencode"
  if [ "$profile" = slim ]; then
    printf '%s\n' '{"plugins":["oh-my-opencode-slim@3.0.6"]}' >"$profile_config_home/opencode/opencode.jsonc"
  else
    : >"$profile_config_home/opencode/opencode.jsonc"
  fi
  opencode_output=$(
    env \
      PATH="$FAKE_BIN:$PATH" \
      HOME="$FAKE_BIN/home" \
      XDG_CONFIG_HOME="$FAKE_BIN/caller-config" \
      OPENCODE_PROFILE_CONFIG_HOME="$profile_config_home" \
      OPENCODE_CONFIG_CONTENT='{"model":"openai/gpt-test"}' \
      "$DOTFILES_ROOT/bin/opencode-profile" "$profile" --prompt "verify $profile"
  )
  assert_opencode_output "xdg=$profile_config_home"
  assert_opencode_output 'content=<unset>'
  assert_opencode_output "args|--standalone|--prompt|verify $profile"
done

printf '%s\n' '{"plugins":["oh-my-opencode-slim@2.2.15"]}' \
  >"$FAKE_BIN/profiles/slim/opencode/opencode.jsonc"
if slim_output=$(env \
  PATH="$FAKE_BIN:$PATH" \
  HOME="$FAKE_BIN/home" \
  OPENCODE_PROFILE_CONFIG_HOME="$FAKE_BIN/profiles/slim" \
  "$DOTFILES_ROOT/bin/opencode-profile" slim 2>&1); then
  printf '%s\n' 'OpenCode V2 Slim profile accepted a V1-only plugin pin' >&2
  printf '%s\n' "$slim_output" >&2
  exit 1
fi
case "$slim_output" in
  *'oh-my-opencode-slim 2.2.15 is V1-only'*) ;;
  *)
    printf '%s\n' 'OpenCode V2 Slim profile returned an unexpected pin failure' >&2
    printf '%s\n' "$slim_output" >&2
    exit 1
    ;;
esac

printf '%s\n' 'OpenCode V2 profile tests: ok'

FAKE_HOME="$FAKE_BIN/home"
mkdir -p "$FAKE_HOME"
cat >"$FAKE_BIN/happier" <<'EOF'
#!/bin/sh

printf 'backend=%s\n' "$HAPPIER_OPENCODE_BACKEND_MODE"
printf 'worker=%s\n' "$HERDR_HAPPIER_WORKER"
printf 'parent_session=%s\n' "${HAPPIER_SESSION_ID-<unset>}"
printf 'state=%s\n' "${HAPPIER_OPENCODE_SERVER_STATE_PATH-<unset>}"
printf 'server_url=%s\n' "${HAPPIER_OPENCODE_SERVER_URL-<unset>}"
printf 'opencode_path=%s\n' "$HAPPIER_OPENCODE_PATH"
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
assert_worker_output "opencode_path=$FAKE_BIN/opencode-v2"
assert_worker_output "config={\"\$schema\":\"https://opencode.ai/config.json#herdr-parent_123-verify-worker\",\"default_agent\":\"herdr-worker\",\"model\":\"openai/gpt-test\"}"
assert_worker_output 'args|opencode|--permission-mode|yolo|--agent-mode|herdr-worker|--model|openai/gpt-test'

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
