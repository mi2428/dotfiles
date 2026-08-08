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
