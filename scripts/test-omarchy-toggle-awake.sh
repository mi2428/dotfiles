#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
export HOME="$tmp/home" MOCK_ROOT="$tmp" PATH="$tmp/bin:$PATH"

cat > "$tmp/bin/systemctl" <<'EOF'
#!/bin/bash
case "$1" in
  is-active) test -e "$MOCK_ROOT/active" ;;
  show) echo 123 ;;
esac
EOF
cat > "$tmp/bin/sudo" <<'EOF'
#!/bin/bash
case "$1 $2" in
  'systemd-run --quiet') touch "$MOCK_ROOT/active" ;;
  'systemctl stop') rm -f "$MOCK_ROOT/active" ;;
  *) exit 1 ;;
esac
EOF
cat > "$tmp/bin/systemd-inhibit" <<'EOF'
#!/bin/bash
printf '[{"pid":123,"who":"omarchy-awake","mode":"block","what":"sleep:handle-lid-switch"}]\n'
EOF
cat > "$tmp/bin/omarchy-toggle-idle" <<'EOF'
#!/bin/bash
file="$HOME/.local/state/omarchy/indicators/stay-awake"
case "$1" in
  stay-awake) if [[ ${MOCK_FAIL_IDLE:-} == 1 ]]; then exit 1; fi
              mkdir -p "${file%/*}"; touch "$file" ;;
  allow-idle) rm -f -- "$file" ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/omarchy-notification-send"
chmod +x "$tmp/bin/"*

awake="$root/bin/omarchy-toggle-awake"
idle="$HOME/.local/state/omarchy/indicators/stay-awake"
owner="$HOME/.local/state/omarchy/awake-idle-owner"
"$awake" >/dev/null
test -f "$idle" && test -f "$owner" && test -f "$tmp/active"
"$awake" >/dev/null
test ! -e "$idle" && test ! -e "$owner" && test ! -e "$tmp/active"

mkdir -p "${idle%/*}"; touch "$idle"
"$awake" >/dev/null
test ! -e "$owner"
"$awake" >/dev/null
test -f "$idle"
rm "$idle"

"$awake" >/dev/null
rm "$tmp/active"
sed -i 's/^[^ ]* /previous-boot /' "$owner"
"$awake" --reconcile
test ! -e "$idle" && test ! -e "$owner"

"$awake" >/dev/null
rm "$tmp/active"
mv "$idle" "$tmp/old-idle"
touch "$idle"
"$awake" --reconcile
test -f "$idle" && test ! -e "$owner"
rm "$idle"

if MOCK_FAIL_IDLE=1 "$awake" >/dev/null 2>&1; then
  echo 'awake succeeded without idle inhibition' >&2; exit 1
fi
test ! -e "$tmp/active" && test ! -e "$owner"
echo 'awake idle checks passed'
