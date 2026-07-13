#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap/verify-source-equivalence.sh --host HOST [--baseline REF]

Compares archived legacy output against the current source layout without
building Home Manager. It compares:

1. The archived legacy output from master:init/LINK
2. The current chezmoi-managed output plus an emulated Home Manager file tree
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
  "$repo_root/bootstrap/bootstrap.sh" --skip-home-manager --host "$host" >/dev/null

link_file() {
  local source="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  ln -sfn "$source" "$destination"
}

materialize_zsh() {
  link_file "$repo_root/home/files/zsh/zshrc" "$current_home/.zshrc"
  link_file "$repo_root/home/files/zsh/zlogin" "$current_home/.zlogin"

  for relative_path in \
    05_catppuccin_theme.zsh \
    10_general.zsh \
    12_general_path.zsh \
    14_general_fzf.zsh \
    20_aliases.zsh \
    22_aliases.zsh \
    30_appearance.zsh \
    40_grc.zsh
  do
    local source_path="$repo_root/home/files/zsh/zsh/$relative_path"
    case "$relative_path:$host" in
      12_general_path.zsh:macos)
        source_path="$repo_root/home/files/zsh/zsh/12_general_path.macos.zsh"
        ;;
      14_general_fzf.zsh:macos)
        source_path="$repo_root/home/files/zsh/zsh/14_general_fzf.macos.zsh"
        ;;
      22_aliases.zsh:macos)
        source_path="$repo_root/home/files/zsh/zsh/22_aliases.macos.zsh"
        ;;
      22_aliases.zsh:docker-dev)
        source_path="$repo_root/home/files/zsh/zsh/22_aliases.docker-dev.zsh"
        ;;
    esac
    link_file "$source_path" "$current_home/.zsh/$relative_path"
  done
}

materialize_git() {
  local gitconfig_source="$repo_root/home/files/git/gitconfig"
  if [[ "$host" == "macos" ]]; then
    gitconfig_source="$repo_root/home/files/git/gitconfig.macos"
  fi

  link_file "$gitconfig_source" "$current_home/.gitconfig"
  link_file "$repo_root/home/files/git/catppuccin-delta.gitconfig" \
    "$current_home/.catppuccin-delta.gitconfig"
}

materialize_nvim() {
  link_file "$repo_root/home/files/config/nvim" "$current_home/.config/nvim"
}

materialize_fish() {
  local relative_paths=(
    config.fish
    fish_plugins
    conf.d/05_catppuccin_theme.fish
    conf.d/10_general.fish
    conf.d/11_starship.fish
    conf.d/12_general_path.fish
    conf.d/13_zoxide.fish
    conf.d/14_fzf_git.fish
    conf.d/15_fzf_theme.fish
    conf.d/20_aliases.fish
    conf.d/21_functions.fish
    conf.d/40_grc.fish
    functions/fish_title.fish
    functions/fish_user_key_bindings.fish
  )

  if [[ "$host" == 'macos' ]]; then
    relative_paths+=(conf.d/22_aliases.fish)
  fi

  for relative_path in "${relative_paths[@]}"; do
    local source_path="$repo_root/home/files/config/fish/$relative_path"
    if [[ "$relative_path" == 'conf.d/12_general_path.fish' && "$host" == 'macos' ]]; then
      source_path="$repo_root/home/files/config/fish/conf.d/12_general_path.macos.fish"
    fi
    link_file "$source_path" "$current_home/.config/fish/$relative_path"
  done
}

materialize_tmux() {
  link_file "$repo_root/home/files/tmux/tmux.conf" "$current_home/.tmux.conf"

  for relative_path in \
    scripts/battery-icon.sh \
    scripts/battery.sh \
    scripts/cpu.sh \
    scripts/mem.sh \
    scripts/storage.sh \
    scripts/window-label.sh \
    statusbar-catppuccin.conf \
    statusbar.conf
  do
    local source_path="$repo_root/home/files/tmux/tmux/$relative_path"
    if [[ "$relative_path" == 'scripts/cpu.sh' && "$host" == 'macos' ]]; then
      source_path="$repo_root/home/files/tmux/tmux/scripts/cpu.macos.sh"
    fi
    if [[ "$relative_path" == 'scripts/mem.sh' && "$host" == 'macos' ]]; then
      source_path="$repo_root/home/files/tmux/tmux/scripts/mem.macos.sh"
    fi
    link_file "$source_path" "$current_home/.tmux/$relative_path"
  done
}

materialize_host_extras() {
  if [[ "$host" == "macos" ]]; then
    link_file \
      "$repo_root/home/files/hosts/macos/karabiner/karabiner.json" \
      "$current_home/.config/karabiner/karabiner.json"
  fi
}

copy_target() {
  local source_home="$1"
  local target_root="$2"
  local relative_path="$3"
  mkdir -p "$target_root/$(dirname "$relative_path")"
  cp -RL "$source_home/$relative_path" "$target_root/$relative_path"
}

materialize_zsh
materialize_git
materialize_nvim
materialize_fish
materialize_tmux
materialize_host_extras

targets=(
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

if [[ "$host" == "macos" ]]; then
  targets+=(.config/karabiner)
fi

for relative_path in "${targets[@]}"; do
  copy_target "$legacy_home" "$legacy_snapshot" "$relative_path"
  copy_target "$current_home" "$current_snapshot" "$relative_path"
done

diff -ru "$legacy_snapshot" "$current_snapshot"

printf '%s\n' "verify: $host source-equivalent to $baseline for ${#targets[@]} targets"
