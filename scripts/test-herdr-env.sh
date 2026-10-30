#!/bin/sh

set -eu

DOTFILES_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
FISH=$(command -v fish)
FAKE_BIN=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN"' EXIT

qa_remove_legacy_file() {
  path=$1
  expected_target=${2:-}
  expected_marker=${3:-}
  if [ -L "$path" ]; then
    [ -n "$expected_target" ] && [ "$(readlink "$path")" = "$expected_target" ] || return 1
    rm -f "$path"
  elif [ -f "$path" ]; then
    first_line=
    [ -n "$expected_marker" ] \
      && IFS= read -r first_line <"$path" \
      && [ "$first_line" = '// installed by herdr' ] \
      && grep -Fxq "// HERDR_INTEGRATION_ID=$expected_marker" "$path" \
      || return 1
    rm -f "$path"
  elif [ -e "$path" ]; then
    return 1
  fi
}

printf '%s\n' \
  'console.log("// installed by herdr")' \
  '// installed by herdr' \
  '// HERDR_INTEGRATION_ID=opencode' \
  >"$FAKE_BIN/user-file"
if qa_remove_legacy_file "$FAKE_BIN/user-file" '' opencode; then
  printf '%s\n' 'Legacy cleanup accepted a user file with a non-leading installer marker' >&2
  exit 1
fi
[ -f "$FAKE_BIN/user-file" ]

printf '%s\n' \
  '// installed by herdr' \
  '// HERDR_INTEGRATION_ID=other' \
  >"$FAKE_BIN/wrong-id"
if qa_remove_legacy_file "$FAKE_BIN/wrong-id" '' opencode; then
  printf '%s\n' 'Legacy cleanup accepted an unexpected integration ID' >&2
  exit 1
fi
[ -f "$FAKE_BIN/wrong-id" ]

printf '%s\n' \
  '// installed by herdr' \
  '// HERDR_INTEGRATION_ID=opencode' \
  >"$FAKE_BIN/managed"
qa_remove_legacy_file "$FAKE_BIN/managed" '' opencode
[ ! -e "$FAKE_BIN/managed" ]

ln -s /known/herdr/source "$FAKE_BIN/known-link"
qa_remove_legacy_file "$FAKE_BIN/known-link" /known/herdr/source
[ ! -L "$FAKE_BIN/known-link" ]

ln -s /other/source "$FAKE_BIN/unknown-link"
if qa_remove_legacy_file "$FAKE_BIN/unknown-link" /known/herdr/source; then
  printf '%s\n' 'Legacy cleanup accepted an unknown symlink target' >&2
  exit 1
fi
[ -L "$FAKE_BIN/unknown-link" ]

printf '%s\n' 'Herdr legacy cleanup tests: ok'

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
printf 'marker=%s\n' "${DOTFILES_OPENCODE_HERDR_PRIVATE_CONFIG-<unset>}"
printf 'args'
for arg in "$@"; do
  printf '|%s' "$arg"
done
printf '\n'
EOF
chmod +x "$FAKE_BIN/opencode-v2"
ln -s "$DOTFILES_ROOT/bin/opencode-profile" "$FAKE_BIN/opencode-profile"

cat >"$FAKE_BIN/opencode" <<'EOF'
#!/bin/sh

if [ "${1:-}" = --version ]; then
  printf 'opencode %s\n' "$FAKE_OPENCODE_VERSION"
  exit 0
fi
printf 'marker=%s\n' "${DOTFILES_OPENCODE_HERDR_PRIVATE_CONFIG-<unset>}"
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
  *'Herdr OpenCode V2 must use the managed private profile'*) ;;
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

herdr_profile_config_home="$FAKE_BIN/profiles/herdr"
mkdir -p "$herdr_profile_config_home/opencode"
printf '%s\n' '{}' >"$herdr_profile_config_home/opencode/opencode.jsonc"
printf '%s\n' '{}' >"$herdr_profile_config_home/opencode/cli.json"

private_launch=$(env \
  PATH="$FAKE_BIN:$PATH" \
  FAKE_OPENCODE_VERSION=v2.2.0 \
  XDG_CONFIG_HOME="$herdr_profile_config_home" \
  HERDR_ENV=1 \
  DOTFILES_OPENCODE_HERDR_PRIVATE_CONFIG="$herdr_profile_config_home/opencode" \
  "$DOTFILES_ROOT/bin/opencode-v2" --standalone --auto)
case "$private_launch" in
  *'marker=<unset>'*'args|--standalone|--auto'*) ;;
  *)
    printf '%s\n' 'OpenCode V2 launcher did not consume the managed private-profile marker' >&2
    printf '%s\n' "$private_launch" >&2
    exit 1
    ;;
esac

if env \
  PATH="$FAKE_BIN:$PATH" \
  FAKE_OPENCODE_VERSION=v2.2.0 \
  XDG_CONFIG_HOME="$herdr_profile_config_home" \
  HERDR_ENV=1 \
  DOTFILES_OPENCODE_HERDR_PRIVATE_CONFIG="$herdr_profile_config_home/opencode" \
  "$DOTFILES_ROOT/bin/opencode-v2" --auto >/dev/null 2>&1; then
  printf '%s\n' 'OpenCode V2 launcher accepted Herdr without --standalone' >&2
  exit 1
fi

if env \
  PATH="$FAKE_BIN:$PATH" \
  FAKE_OPENCODE_VERSION=v2.2.0 \
  XDG_CONFIG_HOME="$herdr_profile_config_home" \
  HERDR_ENV=1 \
  DOTFILES_OPENCODE_HERDR_PRIVATE_CONFIG="$herdr_profile_config_home/opencode" \
  "$DOTFILES_ROOT/bin/opencode-v2" --standalone --server http://127.0.0.1:4096 >/dev/null 2>&1; then
  printf '%s\n' 'OpenCode V2 launcher accepted a shared Herdr server' >&2
  exit 1
fi

if env \
  PATH="$FAKE_BIN:$PATH" \
  FAKE_OPENCODE_VERSION=v2.2.0 \
  XDG_CONFIG_HOME="$herdr_profile_config_home" \
  HERDR_ENV=1 \
  DOTFILES_OPENCODE_HERDR_PRIVATE_CONFIG="$herdr_profile_config_home/opencode" \
  "$DOTFILES_ROOT/bin/opencode-v2" --standalone --attach http://127.0.0.1:4096 >/dev/null 2>&1; then
  printf '%s\n' 'OpenCode V2 launcher accepted a shared Herdr attachment' >&2
  exit 1
fi

opencode_output=$(
  env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$FAKE_BIN/home" \
    XDG_CONFIG_HOME="$FAKE_BIN/default-config" \
    OPENCODE_PROFILE_CONFIG_HOME="$herdr_profile_config_home" \
    OPENCODE_CONFIG_CONTENT='{"model":"openai/gpt-test"}' \
    HERDR_ENV=1 \
    HERDR_AGENT_LAYOUT_WORKER=0 \
    "$FISH" --no-config -c \
      "source '$DOTFILES_ROOT/home/files/config/fish/conf.d/20_aliases.fish'; oc++ --prompt 'verify v2'"
)
assert_opencode_output "xdg=$herdr_profile_config_home"
assert_opencode_output '"default_agent":"herdr-supervisor"'
assert_opencode_output '"model":"openai/gpt-6-sol"'
assert_opencode_output "marker=$herdr_profile_config_home/opencode"
assert_opencode_output 'args|--standalone|--auto|--prompt|verify v2'
case "$opencode_output" in
  *'|--agent|'* | *'|--agent='* | *'|--model|'* | *'|--model='*)
    printf '%s\n' 'OpenCode V2 full-TUI wrapper passed an unsupported agent or model flag' >&2
    printf '%s\n' "$opencode_output" >&2
    exit 1
    ;;
esac

opencode_output=$(
  env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$FAKE_BIN/home" \
    OPENCODE_PROFILE_CONFIG_HOME="$herdr_profile_config_home" \
    HERDR_ENV=1 \
    HERDR_AGENT_LAYOUT_WORKER=1 \
    HERDR_OPENCODE_MODEL=openai/gpt-test \
    "$DOTFILES_ROOT/bin/opencode-profile" herdr --prompt 'verify worker'
)
assert_opencode_output "xdg=$herdr_profile_config_home"
assert_opencode_output '"default_agent":"herdr-worker"'
assert_opencode_output '"model":"openai/gpt-test"'
assert_opencode_output "marker=$herdr_profile_config_home/opencode"
assert_opencode_output 'args|--standalone|--prompt|verify worker'

if env \
  PATH="$FAKE_BIN:$PATH" \
  HOME="$FAKE_BIN/home" \
  OPENCODE_PROFILE_CONFIG_HOME="$herdr_profile_config_home" \
  HERDR_ENV=1 \
  HERDR_AGENT_LAYOUT_WORKER=1 \
  "$DOTFILES_ROOT/bin/opencode-profile" herdr >/dev/null 2>&1; then
  printf '%s\n' 'OpenCode Herdr profile accepted a worker without a verified model' >&2
  exit 1
fi

if env \
  PATH="$FAKE_BIN:$PATH" \
  HOME="$FAKE_BIN/home" \
  OPENCODE_PROFILE_CONFIG_HOME="$herdr_profile_config_home" \
  HERDR_ENV=1 \
  HERDR_AGENT_LAYOUT_WORKER=0 \
  "$DOTFILES_ROOT/bin/opencode-profile" herdr --server http://127.0.0.1:4096 >/dev/null 2>&1; then
  printf '%s\n' 'OpenCode Herdr profile accepted a shared server' >&2
  exit 1
fi

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
      DOTFILES_OPENCODE_HERDR_PRIVATE_CONFIG=/tmp/stale-herdr-profile \
      "$DOTFILES_ROOT/bin/opencode-profile" "$profile" --prompt "verify $profile"
  )
  assert_opencode_output "xdg=$profile_config_home"
  assert_opencode_output 'content=<unset>'
  assert_opencode_output 'marker=<unset>'
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

env PATH="$FAKE_BIN:$PATH" "$FISH" --no-config -c \
  "source '$DOTFILES_ROOT/home/files/config/fish/conf.d/20_aliases.fish'; not functions -q 'oc+++'"
printf '%s\n' 'Happier personal-mode alias isolation: ok'
