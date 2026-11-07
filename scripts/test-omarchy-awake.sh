#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-awake.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/bin"
export AWAKE_TEST_DIR="$scratch"
printf 'inactive\n' >"$scratch/state"
cat >"$scratch/bin/backend" <<'EOF'
#!/bin/sh
set -eu
case "${0##*/}" in
  uname) printf '%s\n' "${TEST_OS:-Linux}" ;;
  sudo) exec "$@" ;;
  systemctl)
    case "$1" in
      is-active) test "$(cat "$AWAKE_TEST_DIR/state")" = active ;;
      show) printf '123\n' ;;
      stop)
        test "${FAIL_STOP:-0}" != 1
        printf 'inactive\n' >"$AWAKE_TEST_DIR/state"
        ;;
      *) exit 2 ;;
    esac
    ;;
  systemd-run)
    test "${FAIL_START:-0}" != 1
    printf '%s\n' "$@" >"$AWAKE_TEST_DIR/arguments"
    printf 'active\n' >"$AWAKE_TEST_DIR/state"
    ;;
  systemd-inhibit)
    if [ "$(cat "$AWAKE_TEST_DIR/state")" = active ] && [ "${NO_INHIBITOR:-0}" != 1 ]; then
      printf '[{"who":"omarchy-awake","pid":123,"what":"sleep:handle-lid-switch","mode":"block"}]\n'
    else
      printf '[{"who":"other","pid":456,"what":"sleep:handle-lid-switch","mode":"block"}]\n'
    fi
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$scratch/bin/backend"
for command in uname sudo systemctl systemd-run systemd-inhibit; do
  ln -s backend "$scratch/bin/$command"
done
export PATH="$scratch/bin:$PATH"
toggle="$root/bin/omarchy-awake-toggle"
test "$(bash "$toggle")" = 'Home awake mode: ON'
test "$(cat "$scratch/state")" = active
for argument in --collect --service-type=exec --what=sleep:handle-lid-switch --mode=block /usr/bin/sleep infinity; do
  grep -qxF -- "$argument" "$scratch/arguments"
done
if FAIL_STOP=1 bash "$toggle" >"$scratch/output" 2>&1; then
  echo 'A failed stop was accepted' >&2
  exit 1
fi
test "$(cat "$scratch/state")" = active
test "$(bash "$toggle")" = 'Home awake mode: OFF'
test "$(cat "$scratch/state")" = inactive
if FAIL_START=1 bash "$toggle" >"$scratch/output" 2>&1; then
  echo 'A failed start was accepted' >&2
  exit 1
fi
test "$(cat "$scratch/state")" = inactive
if NO_INHIBITOR=1 bash "$toggle" >"$scratch/output" 2>&1; then
  echo 'An unrelated inhibitor was accepted' >&2
  exit 1
fi
test "$(cat "$scratch/state")" = inactive
if bash "$toggle" off >"$scratch/output" 2>&1; then
  echo 'An unexpected argument was accepted' >&2
  exit 1
fi
test "$(cat "$scratch/state")" = inactive
if TEST_OS=Darwin bash "$toggle" >"$scratch/output" 2>&1; then
  echo 'A non-Linux host was accepted' >&2
  exit 1
fi
printf '%s\n' 'Home awake toggle, inhibitor verification, and failures: ok'
