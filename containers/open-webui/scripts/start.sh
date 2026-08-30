#!/usr/bin/env bash
set -euo pipefail

ready_marker=/app/backend/data/.declarative-ready
server_pid=

# Invoked by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  rm -f "$ready_marker"
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -TERM "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

rm -f "$ready_marker"
/app/backend/start.sh &
server_pid=$!

for _ in {1..90}; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid" 2>/dev/null || true
    printf '%s\n' 'Open WebUI exited before becoming healthy' >&2
    exit 1
  fi
  curl -fsS "http://127.0.0.1:${PORT:-8080}/health" \
    | jq -e '.status == true' >/dev/null 2>&1 \
    && break
  sleep 1
done
curl -fsS "http://127.0.0.1:${PORT:-8080}/health" | jq -e '.status == true' >/dev/null

/app/backend/declarative-scripts/reconcile.sh /app/backend/declarative
touch "$ready_marker"

set +e
wait "$server_pid"
status=$?
set -e
server_pid=
exit "$status"
