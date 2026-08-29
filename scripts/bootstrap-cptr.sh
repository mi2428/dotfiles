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
  cptr python3 - <<'PY'
import http.cookiejar
import json
import os
import time
import urllib.error
import urllib.request

cookies = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))


def request(path, payload=None, method=None, headers=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        f"http://127.0.0.1:8000{path}",
        data=data,
        method=method,
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    with opener.open(req, timeout=5) as response:
        return json.load(response)


for _ in range(60):
    try:
        config = request("/api/config")
        break
    except Exception:
        time.sleep(1)
else:
    raise SystemExit("Computer did not become ready")

username = os.environ["WEBUI_ADMIN_USERNAME"]
password = os.environ["WEBUI_ADMIN_PASSWORD"]
if config["needs_setup"]:
    token = os.environ["CPTR_STARTUP_TOKEN"]
    if not token:
        raise SystemExit("Computer startup token was not found")
    request("/api/auth/setup", {"username": username, "password": password, "token": token})

request("/api/auth/login", {"username": username, "password": password})

gateway_key = os.environ.get("CPTR_GATEWAY_API_KEY", "")
try:
    request("/v1/models", headers={"Authorization": f"Bearer {gateway_key}"})
except urllib.error.HTTPError as error:
    if error.code != 401:
        raise
    for key in request("/v1/keys"):
        if key["name"] == "Open WebUI":
            request(f"/v1/keys/{key['id']}", method="DELETE")
    print(request("/v1/keys", {"name": "Open WebUI"})["key"])
PY
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
