#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:?repo root is required}"
encrypted_env="$repo_root/secrets/open-webui.env.age"
age_identity="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/key.txt"
recipient_file="$repo_root/chezmoi/.chezmoidata/secrets.yaml"
age_root="$(nix build --no-link --print-out-paths nixpkgs#age)"
age_bin="$age_root/bin/age"
recipient="$(awk -F': ' '/ageRecipient:/ { print $2 }' "$recipient_file" | tail -n 1)"

[[ -s "$encrypted_env" ]] || { printf 'Missing %s\n' "$encrypted_env" >&2; exit 1; }
[[ -s "$age_identity" ]] || { printf 'Missing age identity; run task age.unlock first\n' >&2; exit 1; }
[[ -x "$age_bin" ]] || { printf 'Failed to resolve age from nixpkgs#age\n' >&2; exit 1; }
[[ -n "$recipient" ]] || { printf 'ageRecipient is empty\n' >&2; exit 1; }

umask 077
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/open-webui-env.XXXXXX")"
cipher_temp=
cleanup() {
  rm -rf "$temp_dir"
  [[ -z "$cipher_temp" ]] || rm -f "$cipher_temp"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

plain_env="$temp_dir/env"
original_env="$temp_dir/original"
"$age_bin" --decrypt --identity "$age_identity" --output "$plain_env" "$encrypted_env"
cp "$plain_env" "$original_env"

editor="${VISUAL:-${EDITOR:-vi}}"
read -r -a editor_command <<<"$editor"
case "${editor_command[0]##*/}" in
  vi|vim|nvim) "${editor_command[@]}" -n "$plain_env" ;;
  *) "${editor_command[@]}" "$plain_env" ;;
esac

if cmp -s "$original_env" "$plain_env"; then
  printf '%s\n' 'Open WebUI secret is unchanged'
  exit
fi

allowed='^(#.*|[[:space:]]*|SAKURA_AI_ACCOUNT_TOKEN=.*|WEBUI_SECRET_KEY=.*|WEBUI_ADMIN_USERNAME=.*|WEBUI_ADMIN_EMAIL=.*|WEBUI_ADMIN_PASSWORD=.*|CPTR_WORKSPACE_DIR=.*|OPEN_WEBUI_PORT=.*)$'
if rg -n -v "$allowed" "$plain_env" >/dev/null; then
  printf '%s\n' 'The environment contains an unsupported line' >&2
  exit 1
fi

for key in \
  SAKURA_AI_ACCOUNT_TOKEN \
  WEBUI_SECRET_KEY \
  WEBUI_ADMIN_USERNAME \
  WEBUI_ADMIN_EMAIL \
  WEBUI_ADMIN_PASSWORD \
  CPTR_WORKSPACE_DIR \
  OPEN_WEBUI_PORT; do
  [[ "$(rg -c "^${key}=" "$plain_env" || true)" == 1 ]] || {
    printf '%s must appear exactly once\n' "$key" >&2
    exit 1
  }
done

(
  unset \
    CPTR_WORKSPACE_DIR \
    OPEN_WEBUI_PORT \
    SAKURA_AI_ACCOUNT_TOKEN \
    WEBUI_ADMIN_EMAIL \
    WEBUI_ADMIN_PASSWORD \
    WEBUI_ADMIN_USERNAME \
    WEBUI_SECRET_KEY
  set -a
  # shellcheck disable=SC1090
  source "$plain_env"
  set +a
  : "${SAKURA_AI_ACCOUNT_TOKEN:?set SAKURA_AI_ACCOUNT_TOKEN}"
  : "${WEBUI_SECRET_KEY:?set WEBUI_SECRET_KEY}"
  : "${WEBUI_ADMIN_USERNAME:?set WEBUI_ADMIN_USERNAME}"
  : "${WEBUI_ADMIN_EMAIL:?set WEBUI_ADMIN_EMAIL}"
  : "${WEBUI_ADMIN_PASSWORD:?set WEBUI_ADMIN_PASSWORD}"
  : "${CPTR_WORKSPACE_DIR:?set CPTR_WORKSPACE_DIR}"
  : "${OPEN_WEBUI_PORT:?set OPEN_WEBUI_PORT}"
  [[ -d "$CPTR_WORKSPACE_DIR" ]]
)

cipher_temp="$(mktemp "$encrypted_env.XXXXXX")"
"$age_bin" --encrypt --recipient "$recipient" "$plain_env" > "$cipher_temp"
mv "$cipher_temp" "$encrypted_env"
cipher_temp=
printf '%s\n' 'Open WebUI secret updated'
