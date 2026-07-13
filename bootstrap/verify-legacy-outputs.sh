#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap/verify-legacy-outputs.sh --host HOST [--baseline REF]

Builds a legacy home tree from the baseline ref with the archived init/LINK
script, bootstraps the current tree into a temporary destination, and compares
the resulting materialized outputs.
EOF
}

baseline="${DOTFILES_VERIFY_BASELINE:-master}"
host=""

while (($# > 0)); do
  case "$1" in
    --host)
      host="$2"
      shift 2
      ;;
    --baseline)
      baseline="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '%s\n' "verify: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$host" ]]; then
  printf '%s\n' 'verify: --host is required' >&2
  exit 1
fi

case "$host" in
  macos|linux-server)
    ;;
  *)
    printf '%s\n' "verify: unsupported host '$host'" >&2
    exit 1
    ;;
esac

common_targets=(
  .zshrc
  .zlogin
  .zsh
  .gitconfig
  .catppuccin-delta.gitconfig
  .tmux.conf
  .tmux
  .config/bat
  .config/eza
  .config/fish
  .config/fzf
  .config/ghostty
  .config/glow
  .config/herdr
  .config/hunk
  .config/k9s
  .config/lazygit
  .config/nvim
  .config/starship
  .curlrc
  .lesskey
  .screenrc
  .wgetrc
)

host_targets=()
if [[ "$host" == "macos" ]]; then
  host_targets+=(.config/karabiner)
fi

compare_targets=("${common_targets[@]}" "${host_targets[@]}")

legacy_home="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-legacy-home.XXXXXX")"
legacy_repo="$legacy_home/dotfiles"
current_home="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-current-home.XXXXXX")"
legacy_snapshot="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-legacy-out.XXXXXX")"
current_snapshot="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-current-out.XXXXXX")"

cleanup() {
  rm -rf "$legacy_home" "$current_home" "$legacy_snapshot" "$current_snapshot"
}
trap cleanup EXIT

mkdir -p "$legacy_repo"
git -C "$repo_root" archive "$baseline" | tar -x -C "$legacy_repo"
ln -s "$repo_root" "$current_home/dotfiles"

HOME="$legacy_home" python3 "$legacy_repo/init/LINK" --patch "$host" --force >/dev/null
DOTFILES_HOME="$current_home" \
DOTFILES_USER="${DOTFILES_USER:-teo}" \
  "$repo_root/bootstrap/bootstrap.sh" --host "$host" >/dev/null

copy_target() {
  local source_home="$1"
  local target_root="$2"
  local relative_path="$3"
  local absolute_path="$source_home/$relative_path"

  if [[ ! -e "$absolute_path" && ! -L "$absolute_path" ]]; then
    return 0
  fi

  mkdir -p "$target_root/$(dirname "$relative_path")"
  cp -RL "$absolute_path" "$target_root/$relative_path"
}

for relative_path in "${compare_targets[@]}"; do
  legacy_path="$legacy_home/$relative_path"
  current_path="$current_home/$relative_path"

  if [[ ! -e "$legacy_path" && ! -L "$legacy_path" ]]; then
    printf '%s\n' "verify: missing legacy target: $relative_path" >&2
    exit 1
  fi

  if [[ ! -e "$current_path" && ! -L "$current_path" ]]; then
    printf '%s\n' "verify: missing current target: $relative_path" >&2
    exit 1
  fi

  copy_target "$legacy_home" "$legacy_snapshot" "$relative_path"
  copy_target "$current_home" "$current_snapshot" "$relative_path"
done

diff -ru "$legacy_snapshot" "$current_snapshot"

printf '%s\n' "verify: $host matches $baseline for ${#compare_targets[@]} targets"
