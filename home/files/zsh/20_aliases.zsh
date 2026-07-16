__dotfiles_eza() {
  local -a args=()
  local arg

  if [[ -z ${__DOTFILES_EZA_HYPERLINK_MODE-} ]]; then
    if env -u LS_COLORS -u EXA_COLORS -u EZA_COLORS eza --help 2>/dev/null | grep -Fq -- '--hyperlink [<WHEN>]'; then
      __DOTFILES_EZA_HYPERLINK_MODE='when'
    else
      __DOTFILES_EZA_HYPERLINK_MODE='bare'
    fi
  fi

  for arg in "$@"; do
    if [[ "$arg" == '--hyperlink=auto' ]]; then
      if [[ "$__DOTFILES_EZA_HYPERLINK_MODE" == 'when' ]]; then
        args+=("$arg")
      elif [[ -t 1 ]]; then
        args+=(--hyperlink)
      fi
    else
      args+=("$arg")
    fi
  done

  env -u LS_COLORS -u EXA_COLORS -u EZA_COLORS eza "${args[@]}"
}

__dotfiles_list_dir() {
  if whence -p eza >/dev/null; then
    __dotfiles_eza --icons=auto --group-directories-first --hyperlink=auto .
  elif whence -p exa >/dev/null; then
    EXA_ICON_SPACING=1 exa --icons .
  else
    ls --color=auto .
  fi
}

cd() {
  local cd_status

  if (( $# == 0 )); then
    builtin cd
  else
    builtin cd "$@"
  fi
  cd_status=$?

  (( cd_status == 0 )) && __dotfiles_list_dir
  return $cd_status
}


mcd() {
  [[ -n "${1:-}" ]] || {
    echo 'mcd: missing directory operand' >&2
    return 1
  }
  mkdir -p -- "$1" && cd -- "$1"
}


yy() {
  whence -p yazi >/dev/null || {
    echo 'yy: yazi is not installed' >&2
    return 1
  }

  local cwd_file
  cwd_file="$(mktemp -t yazi-cwd.XXXXXX)" || return 1
  yazi "$@" --cwd-file="$cwd_file"
  local yazi_status=$?

  if [[ -s "$cwd_file" ]]; then
    local new_dir
    new_dir="$(<"$cwd_file")"
    [[ -n "$new_dir" && "$new_dir" != "$PWD" ]] && builtin cd -- "$new_dir"
  fi

  rm -f -- "$cwd_file"
  return $yazi_status
}


pd() {
  if (( $# == 1 )); then
    pushd "$1" >/dev/null
  else
    popd >/dev/null
  fi

  __dotfiles_list_dir
}


bk() {
  local -a positional_args=()
  local -a cp_opts=(-a -i)
  local extension="bk"
  local timestamp_format="+%Y-%m-%dT%H:%M:%S"
  local timestamp_mode=0
  local force_mode=0

  while (( $# > 0 )); do
    case "$1" in
      -e|--extension)
        [[ $# -ge 2 ]] || {
          echo "bk: $1 requires a value" >&2
          return 1
        }
        extension="$2"
        shift 2
        ;;
      -f|--force)
        force_mode=1
        shift
        ;;
      -h|--help)
        echo 'Usage: bk [-f] [-t] [-e EXTENSION] PATH...'
        return 0
        ;;
      -t|--time)
        timestamp_mode=1
        shift
        ;;
      *)
        positional_args+=("$1")
        shift
        ;;
    esac
  done

  (( ${#positional_args[@]} > 0 )) || {
    echo 'bk: no files provided' >&2
    return 1
  }

  (( force_mode )) && cp_opts=(-a -f)

  if (( timestamp_mode )); then
    local backup_dir
    backup_dir="$(date "$timestamp_format")"
    mkdir -p -- "$backup_dir"
    cp "${cp_opts[@]}" -- "${positional_args[@]}" "$backup_dir"
    return $?
  fi

  local path
  for path in "${positional_args[@]}"; do
    cp "${cp_opts[@]}" -- "$path" "${path}.${extension}"
  done
}


goto() {
  local keyword="${1:-/}"
  local matches
  local match_count=0
  local destination=""

  matches="$(grep -i -- "$keyword" "$PATH_BOOKMARK" 2>/dev/null || true)"
  [[ -n "$matches" ]] || {
    echo "goto: no bookmark matched: $keyword" >&2
    return 1
  }

  match_count="$(grep -c '^' <<< "$matches")"
  if (( match_count == 1 )); then
    destination="$matches"
  else
    destination="$(fzf -e --tac --no-sort <<< "$matches" --preview 'tree -L 3 -C {} | head -200')"
  fi

  [[ -n "$destination" ]] || return 1
  /usr/bin/sed -i "" -e "/^${destination//\//\\/}$/d" "$PATH_BOOKMARK"
  printf '%s\n' "$destination" >> "$PATH_BOOKMARK"
  builtin cd -- "$destination"
}


get() {
  mv -i -- "$@" .
}


showopt() {
  set -o | sed -e 's/^no\(.*\)on$/\1  off/' -e 's/^no\(.*\)off$/\1  on/' | \grep --color=auto -E '.*on$|$'
}


__dotfiles_ping() {
  local fallback="$1"
  shift

  if whence -p clockping >/dev/null; then
    clockping icmp --out.colored "$@"
  else
    "$fallback" "$@"
  fi
}

p() {
  if (( $# == 0 )); then
    __dotfiles_ping ping 1.1.1.1
  else
    __dotfiles_ping ping "$@"
  fi
}


pp() {
  if (( $# == 0 )); then
    __dotfiles_ping ping6 2001:4860:4860::8888
  else
    __dotfiles_ping ping6 "$@"
  fi
}


ppp() {
  if whence -p clockping 1> /dev/null; then
    clockping icmp --out.colored -c 4 -i 0.25 8.8.8.8 2001:4860:4860::8888
    clockping http --out.colored -c 4 -i 0.25 ipv4.google.com ipv6.google.com
  else
    ping -c 4 -i 0.25 8.8.8.8
    echo
    ping6 -c 4 -i 0.25 2001:4860:4860::8888
  fi
}


m() {
  if (( $# == 0 )); then
    mtr -4 -b -i 0.1 8.8.8.8
  else
    mtr -4 -b -i 0.1 "$@"
  fi
}


mm() {
  if (( $# == 0 )); then
    mtr -6 -b -i 0.1 2001:4860:4860::8888
  else
    mtr -6 -b -i 0.1 "$@"
  fi
}


mmm() {
  local layout='-v'
  local target='8.8.8.8'
  local quoted_target

  case "${1:-}" in
    -h|-v)
      layout="$1"
      shift
      ;;
  esac

  [[ -n "${1:-}" ]] && target="$1"
  quoted_target="${(q)target}"
  tmux split-window "$layout" -p 66 "sudo grc --colour=auto mtr -4 -b -i 0.1 ${quoted_target}"
  tmux split-window "$layout" "sudo grc --colour=auto mtr -6 -b -i 0.1 ${quoted_target}"
}


dcx() {
  local name="${1:-}"
  local -a args=("${@:2}")

  [[ -n "$name" ]] || {
    echo 'dcx: missing compose service name' >&2
    return 1
  }
  (( ${#args[@]} > 0 )) || args=(/bin/bash)
  docker compose exec "$name" "${args[@]}"
}


dot() {
  if (( $# == 0 )); then
    cd -- "$HOME/dotfiles"
    return 0
  fi

  ## execute in subshell so as not to move current directory
  case $1 in
    cc|commit)
      local message="${@:2}"
      (builtin cd -- "$HOME/dotfiles" 2>/dev/null; git add . >/dev/null 2>&1; git commit -m "$message")
      return 0
      ;;

    k|keep)
      (builtin cd -- "$HOME/dotfiles" 2>/dev/null; git add . >/dev/null 2>&1; git commit -m "keep: $(date)")
      return 0
      ;;

    d|diff)
      (builtin cd -- "$HOME/dotfiles" 2>/dev/null; git diff-index --quiet HEAD || git diff)
      return 0
      ;;

    lg|log)
      (builtin cd -- "$HOME/dotfiles" 2>/dev/null; tig)
      return 0
      ;;

    pl|pull)
      (builtin cd -- "$HOME/dotfiles" 2>/dev/null; git pull)
      return 0
      ;;

    ps|push)
      (builtin cd -- "$HOME/dotfiles" 2>/dev/null; git push)
      return 0
      ;;

    s|sync)
      (builtin cd -- "$HOME/dotfiles" 2>/dev/null; git pull && git push)
      return 0
      ;;

    upgrade)
      if [[ $(uname) == "Darwin" ]]; then
        brew upgrade
      fi
      return 0
      ;;

    rollback)
      (
        builtin cd $HOME/dotfiles 2>/dev/null || exit 1
        if git diff --quiet -- .; then
          echo "dot rollback: no unstaged changes to discard."
        else
          printf "dot rollback: discard unstaged changes in tracked files under ~/dotfiles? [y/N] "
          read -r confirm
          if [[ "$confirm:l" == "y" || "$confirm:l" == "yes" ]]; then
            git restore --worktree -- .
          else
            echo "dot rollback: aborted."
          fi
        fi
      )
      return 0
      ;;

    actions)
      if whence -p open 2>/dev/null 1>&2; then
        open https://github.com/mi2428/dotfiles/actions https://github.com/mi2428/ubuntu/actions
      else
        echo "open your browser and visit:"
        echo " - https://github.com/mi2428/dotfiles/actions"
        echo " - https://github.com/mi2428/ubuntu/actions"
      fi
      return 0
      ;;

    -h|--help|*)
      echo "usage: dot [options...]"
      echo " (empty)               move to $HOME/dotfiles"
      echo " cc, commit [message]  alias of \`git add . && git commit -m\` command"
      echo " k,  keep              alias of \`git keep .\` command"
      echo " d,  diff              alias of \`git diff\` command"
      echo " lg, log               alias of \`tig\` command"
      echo " pl, pull              alias of \`git pull\` command"
      echo " ps, push              alias of \`git push\` command"
      echo " s,  sync              run pull and then push"
      echo "     upgrade           run package upgrade"
      echo "     rollback          discard unstaged tracked-file changes after confirmation"
      echo "     actions           open GitHub Actions"
      echo " h,  help              this help text"
      return 0
      ;;
  esac
}

addr() {
  local addrtxt="$HOME/io/addr/addr.txt"
  local keyword="$1"

  if [[ ! -f "$addrtxt" ]]; then
    echo "missing: ${addrtxt}"
    return 1
  fi

  pushd "$(dirname "$addrtxt")" >/dev/null || return 1
  #git pull 2>/dev/null 1>&2

  if [[ -z "$keyword" ]]; then
    bat "$addrtxt"
  elif [[ "$keyword" == "--edit" ]]; then
    git pull 2>/dev/null || true
    vim "$addrtxt"
    git add "$addrtxt" 2>/dev/null && git commit -m "keep: $(date)" 2>/dev/null && git push 2>/dev/null || true
  else
    local data
    data="$(grep -vE '^(#|$)' "$addrtxt" | grep -i -- "$keyword" || true)"
    if [[ -n "$data" ]]; then
      echo "IP address              Hostname                    Notes"
      printf '%s\n' "$data"
    else
      echo "nothing matched: ${keyword}"
    fi
  fi
}


##
## DEPRECATED:
## Use pimeterry/notes instead (https://github.com/pimterry/notes)
##
# note() {
#   local title="$@"
#   local ts="$(date +%Y.%m.%d-%H:%M:%S)"
# 
#   mkdir -p $NOTEDIR
#   title="${title// /-}"
# 
#   if [[ -n $title ]]; then
#     local filename="${NOTEDIR}/${title}__${ts}.md"
#     $(which $EDITOR) $filename
#   else
#     $(which $EDITOR) -p $(\ls -1rt `find $NOTEDIR -type f -follow` | fzf --multi --preview 'bat --color=always {}')
#   fi
# }


what() {
  local filepath="$1"

  case "$(file -b -- "$filepath")" in
    'PEM certificate')
      openssl x509 -in "$filepath" -noout -text
      ;;
  esac
}


man() {
  # env PAGER="most -s" man $@
  env \
    LESS_TERMCAP_mb=$(printf "\e[1;38;2;%sm" "${CTP_PEACH_RGB}") \
    LESS_TERMCAP_md=$(printf "\e[1;38;2;%sm" "${CTP_PEACH_RGB}") \
    LESS_TERMCAP_me=$(printf "\e[0m") \
    LESS_TERMCAP_se=$(printf "\e[0m") \
    LESS_TERMCAP_so=$(printf "\e[38;2;%s;48;2;%sm" "${CTP_TEXT_RGB}" "${CTP_SURFACE0_RGB}") \
    LESS_TERMCAP_ue=$(printf "\e[0m") \
    LESS_TERMCAP_us=$(printf "\e[4;38;2;%sm" "${CTP_BLUE_RGB}") \
    PAGER=/usr/bin/less \
    _NROFF_U=1 \
    PATH=${HOME}/bin:${PATH} \
  man "$@"
}


tgz() {
  env COPYFILE_DISABLE=1 tar zcvf "$1" --exclude=".DS_Store" "${@:2}"
}


ipapi() {
  if [[ -n "${1:-}" ]]; then
    curl -s "http://ip-api.com/json/${1}" | jq .
  else
    curl -s http://ip-api.com/json | jq .
  fi
}


ghc() {
  local repo="$1"
  if (( $# == 2 )); then
    repo="${1}/${2}"
  fi
  git clone --recursive "git@github.com:${repo}"
}


sshsocks() {
  local host="$1"
  local port="$2"
  ssh -C -D "$port" -f -N "$host"
}


xx() {
  local archive="${1:-}"
  [[ -n "$archive" ]] || {
    echo 'xx: missing archive path' >&2
    return 1
  }

  case "$archive" in
    *.tar.gz|*.tgz) tar xzvf "$archive" ;;
    *.tar.xz) tar Jxvf "$archive" ;;
    *.zip) unzip "$archive" ;;
    *.lzh) lha e "$archive" ;;
    *.tar.bz2|*.tbz) tar xjvf "$archive" ;;
    *.tar.Z) tar zxvf "$archive" ;;
    *.gz) gzip -d "$archive" ;;
    *.bz2) bzip2 -dc "$archive" ;;
    *.Z) uncompress "$archive" ;;
    *.tar) tar xvf "$archive" ;;
    *.arj) unarj "$archive" ;;
    *)
      echo "xx: unsupported archive: $archive" >&2
      return 1
      ;;
  esac
}


dotenv() {
  local _path="$1"

  if [[ ! -f "$_path" ]] && [[ -f .env ]]; then
    _path=".env"
  fi

  [[ -f "$_path" ]] || {
    echo "dotenv: missing env file: $_path" >&2
    return 1
  }

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    export "$line"
  done < "$_path"
}


io() {
  local keywords="$@"

  if [[ -z $keywords ]]; then
    cd $HOME/io
    return 0
  fi
}


::() {
  local session="$1"
  if [[ -z ${session} ]]; then
    tmux
  elif tmux ls -F "#{session_name}" 2>/dev/null | grep -Fxq -- "$session"; then
    tmux attach -t "${session}"
  else
    tmux "$@"
  fi
}


gk() {
  local target="$@"
  if [[ -z $target ]]; then
    target="$(dirname "$(git rev-parse --git-dir)")"
  fi

  git add -- "${target}"
  git commit -m "keep: $(date)"

  if [[ -n $(git remote -v) ]]; then
    git push || git pull && git push
  fi
}


gadd() {
  local selected
  selected=$(unbuffer git status -s | fzf -m --ansi --preview="echo {} | awk '{print \$2}' | xargs git diff --color" | awk '{print $2}')
  if [[ -n "${selected}" ]]; then
    selected=$(tr '\n' ' ' <<< "${selected}")
    git add ${selected}
    echo "Completed: git add ${selected}"
  fi
}


fe() {
  local -a files
  files=("${(@f)$(fzf-tmux --query="$1" --multi --select-1 --exit-0)}")
  (( ${#files[@]} > 0 )) && "${EDITOR:-vim}" "${files[@]}"
}


fkill() {
  local signal="${1:-9}"
  local -a pids

  pids=("${(@f)$(ps -ef | sed 1d | fzf -m | awk '{print $2}')}")
  (( ${#pids[@]} > 0 )) || return 0
  kill "-${signal}" -- "${pids[@]}"
}


dor() {
  local image
  image="$(docker images --format '{{.Repository}}:{{.Tag}}' --filter 'dangling=false' | fzf)" || return $?
  [[ -n "$image" ]] || return 1
  docker run -it "$@" "$image"
}


dox() {
  local container
  container="$(docker ps --format '{{.Names}}' | fzf)" || return $?
  [[ -n "$container" ]] || return 1
  docker exec -it "$container"
}


dorm() {
  local -a containers
  containers=("${(@f)$(docker ps -qa)}")
  (( ${#containers[@]} > 0 )) || return 0
  docker rm "${containers[@]}" 2>/dev/null
}


dormi() {
  local -a images
  images=("${(@f)$(docker images --filter 'dangling=true' -q)}")
  (( ${#images[@]} > 0 )) || return 0
  docker rmi "${images[@]}" 2>/dev/null
}


ffind() {
  local key
  for key in "$@"; do
    find . -name "*${key}*" | grep --color='auto' -- "$key"
  done
}


tenki() {
  curl "http://wttr.in/${1:-}"
}


copy-aws-session() {
  local old_umask
  old_umask="$(umask)"
  mkdir -p "$HOME/.cache"
  umask 077
  cat <<EOS > "$HOME/.cache/zsh__copy_aws_session.cache"
 export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
 export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
 export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
 export AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
EOS
  umask "$old_umask"
  echo "AWS session copied."
}


paste-aws-session() {
  local cache="$HOME/.cache/zsh__copy_aws_session.cache"
  local session

  session="$(<"$cache" 2>/dev/null)"

  if [[ ! -f "$cache" ]] || [[ -z "$session" ]]; then
    echo "Missing cached session."
    return 1
  fi

  if [[ "$1" == "-e" ]]; then
    printf '%s' "$session" | pbcopy 2>/dev/null
    printf '%s' "$session"
  else
    printf '%s' "$session" | sed -e 's/ export //g' -e 's/=/\t/'
  fi

  echo
  eval "$session"
}


clear-aws-session() {
  unset AWS_ACCESS_KEY_ID
  unset AWS_DEFAULT_REGION
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
  echo "AWS session cleared."
}


resolve-vpg-ip() {
  local name="$1"
  local uuid_pattern="^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  if [[ ${name:0:2} == "i-" ]]; then
    aws ec2 describe-instances --filters "Name=instance-id,Values=$name" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress'
    return $?
  fi

  if [[ ${name:0:9} == "VPG-Type-" ]]; then
    aws ec2 describe-instances --filters "Name=tag:Name,Values=$name" | jq -r '.Reservations[].Instances[] | .Placement.AvailabilityZone + " " + .InstanceId + " " + .PrivateIpAddress'
    return $?
  fi

  if [[ $name =~ $uuid_pattern ]]; then
    aws ec2 describe-instances --filters "Name=tag:Name,Values=VPG-Type-*-$name" | jq -r '.Reservations[].Instances[] | .Placement.AvailabilityZone + " " + .InstanceId + " " + .PrivateIpAddress'
    return $?
  fi
}


colortest() {
  for c in {000..255}; do
    echo -n "\e[38;5;${c}m $c"
    (( $(($c%16)) == 15 )) && echo
  done
}


kcc() {
  local context namespace
  context="$(kubectl config current-context 2>/dev/null)" || return $?

  namespace="$(
    kubectl get namespaces -o custom-columns=':metadata.name' --no-headers 2>/dev/null \
      | fzf --prompt='namespace> '
  )" || return 0

  [[ -z "$namespace" ]] && return 0
  kubectl config set-context "$context" --namespace="$namespace"
}


alias -s jl=julia
alias -s py=python3
alias -s rb=ruby
alias -s {gz,tgz,zip,lzh,bz2,tbz,Z,tar,arj,xz}=xx
alias -s {png,jpg,jpeg,bmp,PNG,JPG,JPEG,HEIF,BMP}=preview

alias -g Ia="| awk"
alias -g Iag="| agrep"
alias -g Ic="| pbcopy"
alias -g Ieg="| egrep"
alias -g Ig="| grep"
alias -g Igr="groff -s -p -t -e -Tlatin1 -mandoc"
alias -g Ih="| head"
alias -g Ik="| keep"
alias -g Im="| more"
alias -g Ip="| $PAGER"
alias -g Is="| sort"
alias -g It="| tail"
alias -g Iv="| $EDITOR"
alias -g Iw="| wc"
alias -g Ix="| xargs"

alias '$'=""
alias '%'=""

alias :q='exit'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ..2='cd ../..'
alias ..3='cd ../../..'
alias ..4='cd ../../../..'
alias ..5='cd ../../../../..'

alias b='bat'
alias c='pbcopy'
alias j='jmp'
alias n='notes'
alias o='open'
alias r='rm -i'
alias s='sudo'
alias v='vim -R'
alias x='chmod +x'
alias y='yes'
alias z='exec env PROMPT_SEVERITY=${PROMPT_SEVERITY} OUTSIDE_HOSTNAME=${OUTSIDE_HOSTNAME} zsh --login'

alias an='ansible'
alias be='bundle exec'
alias bi='bundle install'
alias bu='bundle update'
alias d='docker'
alias ga='g a'
alias gb='g b'
alias gc='g c'
alias gd='g d'
alias gf='g f'
alias gp='g p'
alias gs='g s'
alias k='kubectl'
alias ldk='lazydocker'
__git_delta_lazygit() {
  local paging='never'
  local added_label=$'\033[1;38;2;166;227;161mA\033[0m'
  local copied_label=$'\033[1;38;2;148;226;213mC\033[0m'
  local modified_label=$'\033[1;38;2;249;226;175mM\033[0m'
  local removed_label=$'\033[1;38;2;243;139;168mD\033[0m'
  local renamed_label=$'\033[1;38;2;137;180;250mR\033[0m'
  local -a pager_opts=()
  local -a hyperlink_opts=(
    --hyperlinks
    '--hyperlinks-file-link-format=lazygit-edit://{path}:{line}'
  )

  if [[ -t 1 ]]; then
    paging='always'
    # Repaint from the top on half-page jumps to reduce visual artifacts in tmux.
    pager_opts=(--pager 'less -Rc')
  fi

  if [[ -n ${TMUX:-} ]]; then
    hyperlink_opts=()
  fi

  local -a delta_cmd=(
    delta
    --features=catppuccin-lazygit-mocha
    --dark
    "--file-added-label=${added_label}"
    "--file-copied-label=${copied_label}"
    "--file-modified-label=${modified_label}"
    "--file-removed-label=${removed_label}"
    "--file-renamed-label=${renamed_label}"
    "--paging=${paging}"
    "${pager_opts[@]}"
    --line-numbers
    "${hyperlink_opts[@]}"
    --side-by-side
  )

  "${delta_cmd[@]}"
}
__dotfiles_git_handler_name() {
  local subcmd="${1:-}"
  print -r -- "__dotfiles_git_subcommand_${subcmd//-/_}"
}

__dotfiles_git_subcommand_a() {
  command git add "$@"
}

__dotfiles_git_subcommand_aa() {
  command git add -A "$@"
}

__dotfiles_git_subcommand_ac() {
  command git add -A && command git commit -s -m "$*"
}

__dotfiles_git_subcommand_c() {
  command git commit -s -m "$@"
}

__dotfiles_git_subcommand_can() {
  command git commit --amend --no-edit "$@"
}

__dotfiles_git_subcommand_caa() {
  command git commit --amend "$@"
}

__dotfiles_git_subcommand_d() {
  setopt local_options pipefail
  git-delta-input -- "$@" | __git_delta_lazygit
}

__dotfiles_git_subcommand_dd() {
  local base_ref
  setopt local_options pipefail

  if git rev-parse --verify --quiet refs/remotes/origin/HEAD >/dev/null; then
    base_ref='origin/HEAD'
  elif git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; then
    base_ref='origin/main'
  elif git rev-parse --verify --quiet refs/remotes/origin/master >/dev/null; then
    base_ref='origin/master'
  else
    echo 'g dd: could not determine a default base ref (tried origin/HEAD, origin/main, origin/master)' >&2
    return 1
  fi

  git-delta-input --range "${base_ref}...HEAD" -- "$@" | __git_delta_lazygit
}

__dotfiles_git_subcommand_f() {
  command git fetch "$@"
}

__dotfiles_git_subcommand_p() {
  command git push "$@"
}

__dotfiles_git_subcommand_pf() {
  command git push --force-with-lease "$@"
}

__dotfiles_git_subcommand_s() {
  command git status "$@"
}

__dotfiles_git_subcommand_b() {
  if (( $# == 1 )) && [[ "$1" == "-D" ]]; then
    command git-b -D
    return $?
  fi

  if (( $# > 0 )); then
    command git branch "$@"
    return $?
  fi

  local result status_code action arg1 arg2
  result="$(command git-b __resolve-action)"
  status_code=$?
  (( status_code == 0 )) || return $status_code

  IFS=$'\t' read -r action arg1 arg2 _ <<< "$result"
  case "$action" in
    cd)
      builtin cd -- "$arg1" && __dotfiles_list_dir
      ;;
    switch)
      command git switch -- "$arg1"
      ;;
    track)
      command git switch --track -c "$arg1" "$arg2"
      ;;
    *)
      printf 'g b: unknown action: %s\n' "$action" >&2
      return 1
      ;;
  esac
}

__dotfiles_git_subcommand_bm() {
  command git branch -M "$@"
}

__dotfiles_git_subcommand_co() {
  command git checkout "$@"
}

__dotfiles_git_subcommand_dc() {
  command git diff --cached "$@"
}

__dotfiles_git_subcommand_pl() {
  command git pull "$@"
}

__dotfiles_git_subcommand_wa() {
  command git worktree add "$@"
}

__dotfiles_git_subcommand_wr() {
  command git worktree remove "$@"
}

__dotfiles_git_subcommand_clean() {
  command git clean -fd "$@"
}

__dotfiles_git_subcommand_ri() {
  command git rebase -i "$@"
}

__dotfiles_git_subcommand_lg() {
  command git log --oneline --graph --decorate --all "$@"
}

g() {
  if (( $# == 0 )); then
    command git
    return $?
  fi

  local subcmd="$1"
  shift
  local handler
  handler="$(__dotfiles_git_handler_name "$subcmd")"

  if (( $+functions[$handler] )); then
    "$handler" "$@"
  else
    command git "$subcmd" "$@"
  fi
}
alias py='python3'
alias rc='bundle exec rails c'
alias tf='terraform'

alias :::='tmuxinator'
#alias io='cd $HOME/io'
alias dck='docker compose kill && docker compose rm -f'
alias dcl='docker compose logs -f'
alias dcp='docker compose ps -a'
alias dow='cd $HOME/Downloads'
alias ipf='iperf3'
alias ipp='ip -6'
alias ipy='ipython3'
alias jmp='goto'
alias mkd='mkdir -p'
alias ssa='ssh-agent zsh'

alias dcrm='docker compose rm -f'
alias dcup='docker compose up -d && docker compose logs -f'
alias editssh='vim $HOME/.ssh/config'
alias egrep='egrep -n --color=auto'
alias fgrep='fgrep -n --color=auto'
alias free='free -h'
alias grep='grep -n --color=auto'
alias httpserver='python3 -m http.server'
alias less='less --no-init --quit-if-one-screen'
alias myip='curl -s https://ipinfo.io | jq'
alias sshh='sshuttle'


tig() {
  if whence -p lazygit 1> /dev/null; then
    lazygit "$@"
  else
    command tig "$@"
  fi
}


#if whence -p ag 1> /dev/null; then
#  alias grep="ag"
#fi


if whence -p iperf3-rs 1> /dev/null; then
  alias iperf3='iperf3-rs'
fi


if whence -p clockping 1> /dev/null; then
  alias cping='clockping'
fi


if whence -p eza 1> /dev/null; then
  alias l='__dotfiles_eza --icons=auto --group-directories-first --hyperlink=auto'
  alias ls='__dotfiles_eza --icons=auto --group-directories-first --hyperlink=auto'
  alias ll='__dotfiles_eza -l --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto'
  alias la='__dotfiles_eza -l -arbghi --git --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto'
  alias lr='__dotfiles_eza -lR -arbghi --git --git-ignore --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto -I ".git|__pycache__"'
  alias lt='__dotfiles_eza -lT -arbghi --git --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto -I ".git|__pycache__|.terraform"'
  alias laa='__dotfiles_eza -l -arbghi@ --git --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto'
elif whence -p exa 1> /dev/null; then
  export EXA_ICON_SPACING=1
  alias l='exa --icons'
  alias ls='exa --icons'
  alias ll='exa -l --icons'
  alias la='exa -l -arbghi --git --icons'
  alias lr='exa -lR -arbghi --git -I ".git|__pycache__" --icons'
  alias lt='exa -lT -arbghi --git -I ".git|__pycache__|.terraform" --icons'
  alias laa="exa -l -arbghi@ --git --icons"
else
  alias l='ls --color=auto'
  alias ls='ls --color=auto'
  alias ll='ls --color=auto -alF'
  alias la='ls --color=auto -A'
fi


if whence -p htop 1> /dev/null; then
  alias top='htop'
fi


if whence -p vim 1> /dev/null; then
  export EDITOR=vim
  alias vi='vim'
fi


if whence -p nvim 1> /dev/null; then
  export EDITOR=nvim
  alias vi='nvim'
  alias vim='nvim'
  alias emacs='nvim'
  alias nano='nvim'
  alias pico='nvim'
  alias mg='nvim'
fi


if whence -p code 1> /dev/null; then
  alias edit='code'
  alias atom='code'
fi


if whence -p tldr 1> /dev/null; then
  alias h='tldr'
else
  alias h='man'
fi


if whence -p mplayer 1> /dev/null; then
  alias -s {mp3,mp4,wav,mkv,m4v,m4a,wmv,avi,mpeg,mpg,vob,mov,rm}='mplayer'
fi
