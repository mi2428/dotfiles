#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:?repo root is required}"
env_file="$repo_root/containers/open-webui/.env"
compose_file="$repo_root/containers/open-webui/compose.yml"

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

: "${WEBUI_ADMIN_USERNAME:?set WEBUI_ADMIN_USERNAME}"
: "${WEBUI_ADMIN_PASSWORD:?set WEBUI_ADMIN_PASSWORD}"

compose=(docker compose --env-file "$env_file" -f "$compose_file")

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
  export new_gateway_key
  python3 - "$env_file" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
content = path.read_text()
replacement = f"CPTR_GATEWAY_API_KEY={os.environ['new_gateway_key']}"
updated, count = re.subn(r"^CPTR_GATEWAY_API_KEY=.*$", replacement, content, flags=re.MULTILINE)
if count != 1:
    raise SystemExit("CPTR_GATEWAY_API_KEY must appear exactly once in .env")
path.write_text(updated)
PY
fi

printf '%s\n' 'Computer account is ready'
