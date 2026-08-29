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

env_line='^(#.*|[[:space:]]*|[A-Za-z_][A-Za-z0-9_]*=.*)$'
if rg -n -v "$env_line" "$plain_env" >/dev/null; then
  printf '%s\n' 'The environment must contain only comments, blank lines, or KEY=VALUE entries' >&2
  exit 1
fi

cipher_temp="$(mktemp "$encrypted_env.XXXXXX")"
"$age_bin" --encrypt --recipient "$recipient" "$plain_env" > "$cipher_temp"
mv "$cipher_temp" "$encrypted_env"
cipher_temp=
printf '%s\n' 'Open WebUI secret updated'
