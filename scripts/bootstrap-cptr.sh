#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:?repo root is required}"
env_file="$repo_root/containers/open-webui/.env"
compose_file="$repo_root/containers/open-webui/compose.yml"

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

: "${CPTR_ADMIN_USERNAME:?set CPTR_ADMIN_USERNAME}"
: "${CPTR_ADMIN_PASSWORD:?set CPTR_ADMIN_PASSWORD}"

base_url="http://127.0.0.1:${CPTR_PORT:-8000}"
compose=(docker compose --env-file "$env_file" -f "$compose_file")

config=
for _ in {1..60}; do
  if config="$(curl -fsS "$base_url/api/config" 2>/dev/null)"; then
    break
  fi
  sleep 1
done
[[ -n "$config" ]] || { printf '%s\n' 'Computer did not become ready' >&2; exit 1; }

if [[ "$(jq -r '.needs_setup' <<<"$config")" == true ]]; then
  token_line="$("${compose[@]}" logs --no-color cptr | rg -o 'token=[0-9a-f]{64}' | tail -n 1)"
  token="${token_line#token=}"
  [[ -n "$token" ]] || { printf '%s\n' 'Computer startup token was not found' >&2; exit 1; }

  jq -n \
    --arg username "$CPTR_ADMIN_USERNAME" \
    --arg password "$CPTR_ADMIN_PASSWORD" \
    --arg token "$token" \
    '{username: $username, password: $password, token: $token}' \
    | curl -fsS "$base_url/api/auth/setup" \
        -H 'Content-Type: application/json' \
        --data-binary @- \
        >/dev/null
fi

jq -n \
  --arg username "$CPTR_ADMIN_USERNAME" \
  --arg password "$CPTR_ADMIN_PASSWORD" \
  '{username: $username, password: $password}' \
  | curl -fsS "$base_url/api/auth/login" \
      -H 'Content-Type: application/json' \
      --data-binary @- \
      >/dev/null

printf '%s\n' 'Computer account is ready'
