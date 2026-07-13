#!/bin/bash
set -euo pipefail

# IMPORTANT: Starship has built-in git_metrics and git_status modules, but they
# are too slow for very large repositories.
# This helper preserves the same +N / -M and status-symbol visuals while moving
# the expensive Git work behind a tiny cache and an asynchronous refresh path.
# Do not replace this with the stock modules unless performance has been
# re-measured on heavyweight repositories.
ttl_seconds=2
lock_stale_seconds=30
cache_base="${XDG_CACHE_HOME:-$HOME/.cache}/starship/git-metrics"

stat_signature() {
  local target=$1
  if [[ -e "$target" ]]; then
    stat -f '%m:%z' "$target" 2>/dev/null || echo missing
  else
    echo missing
  fi
}

emit_field() {
  local field=$1
  local cache_file=$2
  local green_rgb="${CTP_GREEN_RGB:-166;227;161}"
  local red_rgb="${CTP_RED_RGB:-243;139;168}"
  local peach_rgb="${CTP_PEACH_RGB:-250;179;135}"

  if [[ ! -f "$cache_file" ]]; then
    return 0
  fi

  # shellcheck disable=SC1090
  source "$cache_file"

  case "$field" in
    added)
      if (( ${added:-0} > 0 )); then
        printf ' +%s' "${added}"
      fi
      ;;
    deleted)
      if (( ${deleted:-0} > 0 )); then
        printf ' -%s' "${deleted}"
      fi
      ;;
    status)
      if [[ -n "${status_symbols:-}" ]]; then
        printf ' %s' "${status_symbols}"
      fi
      ;;
    summary)
      if (( ${added:-0} > 0 )); then
        printf '\033[1;38;2;%sm +%s\033[0m' "$green_rgb" "${added}"
      fi
      if (( ${deleted:-0} > 0 )); then
        printf '\033[1;38;2;%sm -%s\033[0m' "$red_rgb" "${deleted}"
      fi
      if [[ -n "${status_symbols:-}" ]]; then
        printf '\033[1;38;2;%sm %s\033[0m' "$peach_rgb" "${status_symbols}"
      fi
      ;;
  esac
}

refresh_cache() {
  local cwd=$1
  local cache_file=$2
  local lock_dir=$3
  local tmp_file
  local repo_root
  local git_dir
  local head
  local index_signature
  local status
  local added=0
  local deleted=0
  local has_changes=0
  local status_symbols=""
  local staged=0
  local dirty=0
  local renamed=0
  local deleted_files=0
  local stashed=0
  local ahead=0
  local behind=0

  if ! mkdir "$lock_dir" 2>/dev/null; then
    exit 0
  fi
  trap 'rmdir "$lock_dir"' EXIT

  cd "$cwd"

  if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    rm -f "$cache_file"
    exit 0
  fi

  git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
  if [[ -z "$git_dir" ]]; then
    rm -f "$cache_file"
    exit 0
  fi
  if [[ "$git_dir" != /* ]]; then
    git_dir="$repo_root/$git_dir"
  fi

  head=$(git -C "$repo_root" rev-parse --verify HEAD 2>/dev/null || echo none)
  index_signature=$(stat_signature "$git_dir/index")
  status=$(git -C "$repo_root" status --porcelain=v2 --branch --ignore-submodules=dirty --untracked-files=no 2>/dev/null || true)

  while IFS= read -r line; do
    case "$line" in
      "# branch.ab "*)
        if [[ "$line" =~ \+([0-9]+)\ -([0-9]+)$ ]]; then
          ahead=${BASH_REMATCH[1]}
          behind=${BASH_REMATCH[2]}
        fi
        ;;
      u\ *)
        dirty=1
        has_changes=1
        ;;
      1\ *|2\ *)
        has_changes=1
        read -r _record xy _rest <<< "$line"
        if [[ ${xy:0:1} != "." ]]; then
          staged=1
          [[ ${xy:0:1} == "R" ]] && renamed=1
          [[ ${xy:0:1} == "D" ]] && deleted_files=1
        fi
        if [[ ${xy:1:1} != "." ]]; then
          dirty=1
          [[ ${xy:1:1} == "R" ]] && renamed=1
          [[ ${xy:1:1} == "D" ]] && deleted_files=1
        fi
        [[ "$xy" == *T* ]] && dirty=1
        ;;
    esac
  done <<< "$status"

  if git -C "$repo_root" ls-files --others --exclude-standard --directory --no-empty-directory | head -n 1 | grep -q .; then
    dirty=1
  fi

  if git -C "$repo_root" rev-parse --verify --quiet refs/stash >/dev/null; then
    stashed=1
  fi

  if (( dirty )); then
    status_symbols="${status_symbols}*"
  fi
  if (( staged )); then
    status_symbols="${status_symbols}+"
  fi
  if (( renamed )); then
    status_symbols="${status_symbols}»"
  fi
  if (( deleted_files )); then
    status_symbols="${status_symbols}✘"
  fi
  if (( stashed )); then
    status_symbols="${status_symbols}≡"
  fi
  if (( ahead > 0 && behind > 0 )); then
    status_symbols="${status_symbols}⇕"
  elif (( ahead > 0 )); then
    status_symbols="${status_symbols}⇡"
  elif (( behind > 0 )); then
    status_symbols="${status_symbols}⇣"
  fi

  if (( has_changes )); then
    while IFS=$'\t' read -r add_count delete_count _path; do
      if [[ "$add_count" =~ ^[0-9]+$ ]]; then
        added=$((added + add_count))
      fi
      if [[ "$delete_count" =~ ^[0-9]+$ ]]; then
        deleted=$((deleted + delete_count))
      fi
    done < <(git -C "$repo_root" diff --numstat HEAD -- 2>/dev/null || true)
  fi

  mkdir -p "$cache_base"
  tmp_file="${cache_file}.tmp.$$"
  {
    printf 'updated_at=%q\n' "$(date +%s)"
    printf 'head=%q\n' "$head"
    printf 'index_signature=%q\n' "$index_signature"
    printf 'status_symbols=%q\n' "$status_symbols"
    printf 'added=%q\n' "$added"
    printf 'deleted=%q\n' "$deleted"
  } > "$tmp_file"
  mv "$tmp_file" "$cache_file"
}

if [[ ${1:-} == "--refresh" ]]; then
  refresh_cache "$2" "$3" "$4"
  exit 0
fi

field=${1:-}
if [[ "$field" != "added" && "$field" != "deleted" && "$field" != "status" && "$field" != "summary" ]]; then
  exit 0
fi

mkdir -p "$cache_base"
cache_key=$(printf '%s\n' "$PWD" | shasum | awk '{print $1}')
cache_file="$cache_base/$cache_key.env"
lock_dir="$cache_base/$cache_key.lock"
now=$(date +%s)
needs_refresh=0

if [[ -f "$cache_file" ]]; then
  # shellcheck disable=SC1090
  source "$cache_file"
  if (( now - ${updated_at:-0} >= ttl_seconds )); then
    needs_refresh=1
  fi
else
  needs_refresh=1
fi

if [[ -d "$lock_dir" ]]; then
  lock_age=$((now - $(stat -f '%m' "$lock_dir" 2>/dev/null || echo 0)))
  if (( lock_age >= lock_stale_seconds )); then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
fi

if (( needs_refresh )) && [[ ! -d "$lock_dir" ]]; then
  nohup "$0" --refresh "$PWD" "$cache_file" "$lock_dir" >/dev/null 2>&1 &
fi

emit_field "$field" "$cache_file"
