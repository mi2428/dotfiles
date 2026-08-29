#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:?repo root is required}"
action="${2:?action is required}"

encrypted_env="$repo_root/secrets/open-webui.env.age"
age_identity="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/key.txt"
gateway_env_file="${XDG_STATE_HOME:-$HOME/.local/state}/open-webui/cptr-gateway.env"
age_root="$(nix build --no-link --print-out-paths nixpkgs#age)"
age_bin="$age_root/bin/age"

[[ -s "$encrypted_env" ]] || { printf 'Missing %s\n' "$encrypted_env" >&2; exit 1; }
[[ -s "$age_identity" ]] || { printf 'Missing age identity; run task age.unlock first\n' >&2; exit 1; }
[[ -x "$age_bin" ]] || { printf 'Failed to resolve age from nixpkgs#age\n' >&2; exit 1; }

unset \
  CPTR_GATEWAY_API_KEY \
  CPTR_WORKSPACE_DIR \
  OPEN_TERMINAL_API_KEY \
  OPEN_WEBUI_PORT \
  SAKURA_AI_ACCOUNT_TOKEN \
  WEBUI_ADMIN_EMAIL \
  WEBUI_ADMIN_PASSWORD \
  WEBUI_ADMIN_USERNAME \
  WEBUI_SECRET_KEY
set -a
# shellcheck disable=SC1090
source <("$age_bin" --decrypt --identity "$age_identity" "$encrypted_env")
decrypt_pid=$!
set +a
wait "$decrypt_pid"

: "${SAKURA_AI_ACCOUNT_TOKEN:?set SAKURA_AI_ACCOUNT_TOKEN}"
: "${WEBUI_SECRET_KEY:?set WEBUI_SECRET_KEY}"
: "${WEBUI_ADMIN_USERNAME:?set WEBUI_ADMIN_USERNAME}"
: "${WEBUI_ADMIN_EMAIL:?set WEBUI_ADMIN_EMAIL}"
: "${WEBUI_ADMIN_PASSWORD:?set WEBUI_ADMIN_PASSWORD}"
: "${CPTR_WORKSPACE_DIR:?set CPTR_WORKSPACE_DIR}"
: "${OPEN_TERMINAL_API_KEY:?set OPEN_TERMINAL_API_KEY}"
[[ -d "$CPTR_WORKSPACE_DIR" ]] || { printf 'CPTR_WORKSPACE_DIR is not a directory\n' >&2; exit 1; }

unset CPTR_GATEWAY_API_KEY
set -a
# shellcheck disable=SC1090
[[ ! -f "$gateway_env_file" ]] || source "$gateway_env_file"
set +a

compose=(docker compose -f "$repo_root/containers/open-webui/compose.yml")

case "$action" in
  up)
    "${compose[@]}" up -d cptr
    "$repo_root/scripts/bootstrap-cptr.sh" "$repo_root"
    unset CPTR_GATEWAY_API_KEY
    set -a
    # shellcheck disable=SC1090
    source "$gateway_env_file"
    set +a
    "${compose[@]}" up -d --build
    "$repo_root/scripts/bootstrap-open-webui.sh" "$repo_root"
    ;;
  down)
    "${compose[@]}" down
    ;;
  logs)
    "${compose[@]}" logs -f
    ;;
  *)
    printf 'Unknown action: %s\n' "$action" >&2
    exit 1
    ;;
esac
