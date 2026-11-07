#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/pacman-sync.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/bin"
export PACMAN_TEST_DIR="$scratch" REAL_GREP
REAL_GREP=$(command -v grep)
cat >"$scratch/bin/backend" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${0##*/}" in
  uname) printf 'Linux\n' ;;
  grep)
    if [[ ${*: -1} == /etc/os-release ]]; then exit 0; fi
    exec "$REAL_GREP" "$@"
    ;;
  sudo) exec "$@" ;;
  pacman-conf)
    printf 'core\nextra\n'
    if [[ ${OMARCHY_REPO:-1} == 1 ]]; then printf 'omarchy\n'; fi
    ;;
  pacman)
    [[ $* == '-Syu --needed -' ]]
    cat >"$PACMAN_TEST_DIR/packages"
    printf 'pacman\n' >>"$PACMAN_TEST_DIR/calls"
    [[ ${FAIL_PACMAN:-0} != 1 ]]
    ;;
  mise)
    [[ $# == 2 && $1 == install && ( $2 == node || $2 == opencode ) ]]
    printf 'mise %s\n' "$*" >>"$PACMAN_TEST_DIR/calls"
    [[ ${FAIL_MISE:-} != "$2" ]]
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$scratch/bin/backend"
for command in uname grep sudo pacman-conf pacman mise; do
  ln -s backend "$scratch/bin/$command"
done
export PATH="$scratch/bin:$PATH"
run() {
  : >"$scratch/calls"
  task --dir "$root" pacman.sync >"$scratch/output" 2>&1
}
expect_calls() {
  printf '%s\n' "$@" >"$scratch/expected-calls"
  cmp "$scratch/expected-calls" "$scratch/calls"
}

run
expect_calls pacman 'mise install node' 'mise install opencode'
cat "$root/packages/pacman.txt" "$root/packages/omarchy.txt" >"$scratch/expected-packages"
cmp "$scratch/expected-packages" "$scratch/packages"
OMARCHY_REPO=0 run
expect_calls pacman
cmp "$root/packages/pacman.txt" "$scratch/packages"
if FAIL_PACMAN=1 run; then
  echo 'A failed package installation was accepted' >&2
  exit 1
fi
expect_calls pacman
if FAIL_MISE=node run; then
  echo 'A failed Node installation was accepted' >&2
  exit 1
fi
expect_calls pacman 'mise install node'
if FAIL_MISE=opencode run; then
  echo 'A failed OpenCode installation was accepted' >&2
  exit 1
fi
expect_calls pacman 'mise install node' 'mise install opencode'
printf '%s\n' 'Package selection, ordered Omarchy tool installation, and failures: ok'
