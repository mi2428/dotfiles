#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:?repository root is required}"
profile_file="$repo_root/containers/open-webui/profile.webp"

: "${WEBUI_ADMIN_USERNAME:?set WEBUI_ADMIN_USERNAME}"
: "${WEBUI_ADMIN_EMAIL:?set WEBUI_ADMIN_EMAIL}"
: "${WEBUI_ADMIN_PASSWORD:?set WEBUI_ADMIN_PASSWORD}"

base_url="http://127.0.0.1:${OPEN_WEBUI_PORT:-8080}"
compose=(docker compose -f "$repo_root/containers/open-webui/compose.yml")
marker=/app/backend/data/.profile-provisioned

for _ in {1..90}; do
  if curl -fsS "$base_url/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS "$base_url/health" >/dev/null

if "${compose[@]}" exec -T open-webui test -f "$marker"; then
  printf '%s\n' 'Open WebUI profile is ready'
  exit
fi

token="$({
  jq -n \
    --arg email "$WEBUI_ADMIN_EMAIL" \
    --arg password "$WEBUI_ADMIN_PASSWORD" \
    '{email: $email, password: $password}' \
    | curl -fsS "$base_url/api/v1/auths/signin" \
        -H 'Content-Type: application/json' \
        --data-binary @-
} | jq -er '.token')"
profile_image_url="data:image/webp;base64,$(base64 <"$profile_file" | tr -d '\n')"

jq -n \
  --arg name "$WEBUI_ADMIN_USERNAME" \
  --arg profile_image_url "$profile_image_url" \
  '{name: $name, profile_image_url: $profile_image_url, bio: null, gender: null, date_of_birth: null}' \
  | curl -fsS "$base_url/api/v1/auths/update/profile" \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $token" \
      --data-binary @- \
      | jq -e '.profile_image_url | startswith("data:image/webp;base64,")' \
      >/dev/null

"${compose[@]}" exec -T open-webui touch "$marker"
printf '%s\n' 'Open WebUI profile is ready'
