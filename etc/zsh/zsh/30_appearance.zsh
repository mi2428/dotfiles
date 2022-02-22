typeset -gA PROMPT_SYMBOL=(
  corner.top     '╭─'
  corner.bottom  '╰─'
  arrow          '─▶'
  path.marked    '♣ '
  #arrow          '─▶▶'
  #arrow          '─▷'
  #arrow          '─▷▷'
)


typeset -g KAWAII_EMOJI=(
  '(๑˃̵ᴗ˂̵)و'
  #'(๑•̀ㅂ•́)و'
  #'(๑°ω°๑)و'
  #'(๑•ㅂ•)و'
  #'(๑ᵒᗜ ᵒ)و'
)


typeset -gA PROMPT_PALETTE=(
  host          '%b%u%F{157}'
  insidehost    '%b%u%F{194}'
  user          '%b%u%F{253}'
  path          '%B%u%F{229}'
  path.shrinked '%B%u%F{226}'
  path.marked   '%B%u%F{144}'
  venv          '%b%u%F{081}'
  ssh.via       '%b%u%F{222}'
  ssh.agent     '%b%u%F{081}'
  time          '%b%u%F{247}'
  elapsed       '%b%u%F{222}'
  exit.mark     '%b%u%F{246}'
  exit.code     '%B%u%F{203}'
  git.commited  '%b%u%F{038}'
  git.staged    '%b%u%F{226}'
  git.modified  '%b%u%F{009}'
  git.untracked '%b%u%F{208}'
  conj          '%b%u%F{102}'
  typing        '%b%u%F{252}'
  normal        '%b%u%F{252}'
  cursor        '%b%u%F{252}'
  level0        '%b%u%F{252}'
  level1        '%b%u%F{014}'
  level2        '%b%u%F{003}'
  level3        '%b%u%F{208}'
  level4        '%b%u%F{009}'
  underline     '%b%U%F{252}'
  success       '%b%u%F{013}'
  error         '%b%u%F{203}'
  reset         '%{\e[00m%}'
)


typeset -gA prompts=(
  margin     ""
  host       ""
  user       ""
  level      ""
  path       ""
  path.icon  ""
  venv       ""
  ssh.via    ""
  ssh.agent  ""
  git        ""
  time       ""
  elapsed    ""
  typing     ""
  exit       ""
)


typeset -gA prompts_len=(
  margin     0
  host       0
  user       0
  path       0
  path.icon  0
  venv       0
  ssh.via    0
  ssh.agent  0
  git        0
  time       0
  elapsed    0
  exit       0
)


typeset -gi exec_timestamp=0


set_severity_level() {
  case ${PROMPT_SEVERITY} in
    1)
      PROMPT_PALETTE[cursor]=${PROMPT_PALETTE[level1]}
      prompts[level]="${PROMPT_PALETTE[cursor]} ♨ "
      prompts_len[level]=$(( 2 + 2 * 1 ))
      ;;
    2)
      PROMPT_PALETTE[cursor]=${PROMPT_PALETTE[level2]}
      prompts[level]="${PROMPT_PALETTE[cursor]} ♨ ♨ "
      prompts_len[level]=$(( 2 + 2 * 2 ))
      ;;
    3)
      PROMPT_PALETTE[cursor]=${PROMPT_PALETTE[level3]}
      prompts[level]="${PROMPT_PALETTE[cursor]} ♨ ♨ ♨ "
      prompts_len[level]=$(( 2 + 2 * 3 ))
      ;;
    4)
      PROMPT_PALETTE[cursor]=${PROMPT_PALETTE[level4]}
      prompts[level]="${PROMPT_PALETTE[cursor]} ♨ ♨ ♨ ♨ "
      prompts_len[level]=$(( 2 + 2 * 4 ))
      ;;
    0|*)
      PROMPT_PALETTE[cursor]=${PROMPT_PALETTE[level0]}
      prompts[level]=""
      prompts_len[level]=0
      PROMPT_SEVERITY=0
      ;;
  esac
}


set_exec_timestamp() {
  exec_timestamp=$(date +%s)
}


set_margin() {
  if [[ -n $NEW_LINE_BEFORE_PROMPT ]] && (( LINES > 16 )); then
    prompts[margin]="${PROMPT_PALETTE[reset]}\n"
  else
    NEW_LINE_BEFORE_PROMPT=true
  fi
}


set_hostname() {
  local name=${(%):-%M}
  if [[ -z ${OUTSIDE_HOSTNAME} ]]; then
    prompts[host]="${PROMPT_PALETTE[cursor]}[${PROMPT_PALETTE[host]}${name}${PROMPT_PALETTE[cursor]}]"
    prompts_len[host]=$(( ${#name} + 2 ))
  else
    local inside="${PROMPT_PALETTE[cursor]}[${PROMPT_PALETTE[insidehost]}${name}${PROMPT_PALETTE[cursor]}]"
    local outside="${PROMPT_PALETTE[cursor]}[${PROMPT_PALETTE[host]}${OUTSIDE_HOSTNAME}${PROMPT_PALETTE[cursor]}]"
    prompts[host]="${outside}╌${inside}"
    prompts_len[host]=$(( ${#name} + ${#OUTSIDE_HOSTNAME} + 5 ))
  fi
}


set_user() {
  local user=${(%):-%n}
  local user_color=${PROMPT_PALETTE[user]}
  if (( $EUID == 0 )); then
    user_color=${PROMPT_PALETTE[root]}
  fi
  prompts[user]=" ${PROMPT_PALETTE[conj]}as ${user_color}${user}"
  prompts_len[user]=$(( ${#user} + 4 ))
}


set_path_icon() {
  prompts[path.icon]=""
  prompts_len[path.icon]=0
  if \grep -q "^${PWD}$" "$PATH_BOOKMARK"; then
    prompts[path.icon]="${PROMPT_PALETTE[path.marked]}${PROMPT_SYMBOL[path.marked]}${PROMPT_PALETTE[reset]} "
    prompts_len[path.icon]=$(( ${#prompts_len[path.icon]} + 2 ))
  fi
}


calc_path_length() {
  local current_path="$1"
  local total_chars=$(LC_CTYPE=ja_JP.UTF-8 wc -m <<< ${current_path})
  local total_bytes=$(LC_CTYPE=ja_JP.UTF-8 wc -c <<< ${current_path})
  local zenkaku_bytes=3
  local zenkaku_width=2
  local n_hankaku=$(( (zenkaku_bytes * total_chars - total_bytes ) / 2 ))
  local n_zenkaku=$(( (total_bytes - total_chars) / 2 ))
  echo $(( n_hankaku + zenkaku_width * n_zenkaku ))
}


set_current_path() {
  LC_CTYPE=ja_JP.UTF-8 local current_path=${(%):-%~}
  prompts[path]=" ${PROMPT_PALETTE[conj]}in ${prompts[path.icon]}${PROMPT_PALETTE[path]}${current_path}"
  prompts_len[path]=$(( $(calc_path_length "$current_path") + 4 ))
}


shrink_path() {
  local fullpath="$1"
  local level="$2"
  local elements
  local shrinked=""
  local len=0

  IFS='/' read -rA elements <<< "${fullpath}"
  for e in "${elements[@]}"; do
    if [[ -z $e ]]; then
      continue
    fi
    if [[ "$e" == "~" ]]; then
      shrinked="~"
      len=$(( len + 1 ))
      continue
    fi
    if [[ -z ${shrinked} ]]; then
      shrinked="/${e}"
      len=$(( len + $#e + 1 ))
      continue
    fi
    if (( level > 0 )); then
      shrinked="${shrinked}${PROMPT_PALETTE[path]}/${PROMPT_PALETTE[path.shrinked]}${e:0:1}${PROMPT_PALETTE[path]}"
      level=$(( level - 1 ))
      len=$(( len + 2 ))
    else
      shrinked="${shrinked}${PROMPT_PALETTE[path]}/${e}"
      len=$(( len + $#e + 1 ))
    fi
  done
  echo "${shrinked} ${len}"
}


set_shrink_path() {
  local width_budget="$1"
  LC_CTYPE=ja_JP.UTF-8 local current_path=${(%):-%~}
  local p=${prompts[path]}
  local l=${prompts_len[path]}
  local level=0
  local depth=$(awk '{count += (split($0, a, "/") - 1)} END{print count}' <<< $current_path)
  while (( level <= depth )) && (( l >= width_budget )); do
    read shrinked shrinked_len < <(shrink_path ${current_path} $level)
    p=" ${PROMPT_PALETTE[conj]}in ${prompts[path.icon]}${PROMPT_PALETTE[path]}${shrinked}"
    l=$(( shrinked_len + 4 ))
    level=$(( level + 1 ))
  done
  prompts[path]="$p"
  prompts_len[path]="$l"
}


set_current_time() {
  local current_time=${(%):-%D{%H:%M:%S}}
  prompts[time]="${PROMPT_PALETTE[time]}${current_time}"
  prompts_len[time]=${#current_time}
}


set_elapsed_time() {
  if (( exec_timestamp > 0 )); then
    local exec_seconds=" +$(( $(date +%s) - exec_timestamp ))sec"
    prompts[elapsed]="${PROMPT_PALETTE[elapsed]}${exec_seconds}"
    prompts_len[elapsed]=${#exec_seconds}
    exec_timestamp=0
  else
    prompts[elapsed]=""
    prompts_len[elapsed]=0
  fi
}


set_git_info() {
  local timeout_sec=0.01
  #local git_branch=${$( timeout ${timeout_sec} git branch --show-current 2>&1 ):-?}
  local git_branch=${$( git branch --show-current 2>&1 ):-?}
  if [[ ${git_branch} == "?" ]]; then
    prompts[git]=" ${PROMPT_PALETTE[conj]}with ${PROMPT_PALETTE[git.commited]}git"
    prompts_len[git]=9
  elif [[ -z ${git_branch} ]] || [[ ${git_branch} =~ " a git repository" ]]; then
    prompts[git]=""
    prompts_len[git]=0
  else
    local git_status="$(git status 2> /dev/null)"
    local color="${PROMPT_PALETTE[git.commited]}"
    if [[ ${git_status} =~ "Changes to be committed:" ]]; then
      color="${PROMPT_PALETTE[git.staged]}"
    elif [[ ${git_status} =~ "Changes not staged for commit:" ]]; then
      color="${PROMPT_PALETTE[git.modified]}"
    elif [[ ${git_status} =~ "Untracked files:" ]]; then
      color="${PROMPT_PALETTE[git.untracked]}"
    fi
    #prompts[git]=" ${PROMPT_PALETTE[conj]}on ${PROMPT_PALETTE[normal]}(${color}${git_branch}${PROMPT_PALETTE[normal]})"
    prompts[git]=" ${PROMPT_PALETTE[conj]}on ${color}${git_branch}"
    prompts_len[git]=$(( ${#git_branch} + 4 ))
  fi
}


set_venv_info() {
  if [[ -n ${VIRTUAL_ENV} ]]; then
    prompts[venv]="${PROMPT_PALETTE[normal]}(${PROMPT_PALETTE[venv]}venv${PROMPT_PALETTE[normal]})"
    prompts_len[venv]=5
  else
    prompts[venv]=""
    prompts_len[venv]=0
  fi
}


mask_ip() {
  local rawip="$1"
  [[ ${rawip} =~ '\.' ]] && echo "***.$(awk -F'.' '{print $NF}' <<< ${rawip})"
  [[ ${rawip} =~ ':' ]] && echo "****:$(awk -F':' '{print $NF}' <<< ${rawip})"
}


set_via_ssh_info() {
  local srcip=$(awk '{print $1}' <<< ${SSH_CLIENT})
  if [[ -n ${srcip} ]] && ( [[ -z ${HIDE_SSH_PROMPT} ]] || [[ ${HIDE_SSH_PROMPT} == 0 ]] ); then
    local maskedip=$(mask_ip ${srcip})
    prompts[ssh.via]=" ${PROMPT_PALETTE[conj]}via ${PROMPT_PALETTE[ssh.via]}${maskedip} (SSH)${PROMPT_PALETTE[normal]}"
    prompts_len[ssh.via]=$(( ${#maskedip} + 11 ))
  else
    prompts[ssh.via]=""
    prompts_len[ssh.via]=0
  fi
}


set_ssh_agent_info() {
  if [[ -n ${SSH_AGENT_PID} ]]; then
    prompts[ssh.agent]=" ${PROMPT_PALETTE[conj]}on ${PROMPT_PALETTE[ssh.agent]}ssh-agent${PROMPT_PALETTE[normal]}"
    prompts_len[ssh.agent]=13
  else
    prompts[ssh.agent]=""
    prompts_len[ssh.agent]=0
  fi
}


set_last_status() {
  local last_code=$?
  if (( ${last_code} == 0 )); then
    local emoji=${KAWAII_EMOJI[$(( $RANDOM % ${#KAWAII_EMOJI[@]} + 1 ))]}
    prompts[exit]="${PROMPT_PALETTE[success]}${emoji}"
    prompts_len[exit]=$#emoji
  else
    prompts[exit]="${PROMPT_PALETTE[exit.mark]}exit:${PROMPT_PALETTE[exit.code]}${last_code}"
    prompts_len[exit]=$(( ${#last_code} + 5 ))
  fi
}


set_typing_pointer() {
  prompts[typing]="${PROMPT_SYMBOL[arrow]}${PROMPT_PALETTE[reset]}"
}


main_prompt() {
  local width=$(tput cols)
  local prompt_len_wo_path=$(( prompts_len[host] + prompts_len[level] + prompts_len[path.icon]
                               + prompts_len[git] + prompts_len[ssh.agent] + prompts_len[ssh.via]
                               + prompts_len[time] + prompts_len[elapsed] ))
  local path_len_budget="$(( width - prompt_len_wo_path - 2))"

  set_shrink_path ${path_len_budget}

  local corner_top="${prompts[margin]}${PROMPT_PALETTE[cursor]}${PROMPT_SYMBOL[corner.top]}"
  local corner_bottom="${PROMPT_PALETTE[reset]}${PROMPT_PALETTE[cursor]}${PROMPT_SYMBOL[corner.bottom]}"
  local left_part="${corner_top}${prompts[host]}${prompts[level]}${prompts[path]}${prompts[git]}${prompts[ssh.agent]}${prompts[ssh.via]}"
  local right_part="${prompts[time]}${prompts[elapsed]}"
  local prompt_len=$(( prompt_len_wo_path + prompts_len[path] ))
  local padding="$(( width - prompt_len - 2))"

  if (( padding > 0 )); then
    echo "${left_part}${(r:${padding}:)""}${right_part}${PROMPT_PALETTE[normal]}"
  else
    echo "${left_part}${PROMPT_PALETTE[reset]}"
  fi
  echo "${corner_bottom}${prompts[venv]}${prompts[typing]}${PROMPT_PALETTE[normal]} "
}


sub_prompt() {
  echo "${prompts[exit]}${PROMPT_PALETTE[normal]}"
}


preexec() {
  set_exec_timestamp
}


precmd() {
  set_last_status  # must be loaded at first!
  set_severity_level
  set_margin
  set_hostname
  set_user
  set_path_icon  # must be loaded before set_current_path
  set_current_path
  set_current_time
  set_elapsed_time
  set_git_info
  set_venv_info
  set_via_ssh_info
  set_ssh_agent_info
  set_typing_pointer
}


PROMPT='$(main_prompt)'
RPROMPT='$(sub_prompt)'
