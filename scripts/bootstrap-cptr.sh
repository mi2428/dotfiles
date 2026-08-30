#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:?repo root is required}"
gateway_env_file="${XDG_STATE_HOME:-$HOME/.local/state}/open-webui/cptr-gateway.env"

: "${WEBUI_ADMIN_USERNAME:?set WEBUI_ADMIN_USERNAME}"
: "${WEBUI_ADMIN_PASSWORD:?set WEBUI_ADMIN_PASSWORD}"

compose=(docker compose -f "$repo_root/containers/open-webui/compose.yml")

export CPTR_STARTUP_TOKEN=
for _ in {1..60}; do
  token_line="$("${compose[@]}" logs --no-color cptr | rg -o 'token=[0-9a-f]{64}' | tail -n 1 || true)"
  CPTR_STARTUP_TOKEN="${token_line#token=}"
  if [[ -n "$CPTR_STARTUP_TOKEN" ]]; then
    break
  fi
  sleep 1
done

new_gateway_key="$("${compose[@]}" exec -T \
  -e WEBUI_ADMIN_USERNAME \
  -e WEBUI_ADMIN_PASSWORD \
  -e CPTR_STARTUP_TOKEN \
  -e CPTR_GATEWAY_API_KEY \
  cptr python3 /usr/local/libexec/bootstrap_cptr.py
)"

if [[ -n "$new_gateway_key" ]]; then
  mkdir -p "${gateway_env_file%/*}"
  chmod 700 "${gateway_env_file%/*}"
  umask 077
  printf '%s\n' \
    '# Machine-local Gateway API key used by Open WebUI to call Computer.' \
    "CPTR_GATEWAY_API_KEY=$new_gateway_key" \
    > "$gateway_env_file"
fi

printf '%s\n' 'Computer account is ready'
