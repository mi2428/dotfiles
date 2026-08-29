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

token_line="$("${compose[@]}" logs --no-color cptr | rg -o 'token=[0-9a-f]{64}' | tail -n 1 || true)"
export CPTR_STARTUP_TOKEN="${token_line#token=}"

"${compose[@]}" exec -T \
  -e WEBUI_ADMIN_USERNAME \
  -e WEBUI_ADMIN_PASSWORD \
  -e CPTR_STARTUP_TOKEN \
  cptr python3 - <<'PY'
import json
import os
import time
import urllib.request


def request(path, payload=None):
    data = json.dumps(payload).encode() if payload else None
    req = urllib.request.Request(
        f"http://127.0.0.1:8000{path}",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=5) as response:
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
PY

printf '%s\n' 'Computer account is ready'
