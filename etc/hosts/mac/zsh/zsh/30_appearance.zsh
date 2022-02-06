typeset -gA PROMPT_SYMBOL=(
  corner.top     '╭─'
  corner.bottom  '╰─'
  arrow          '─▶'
)


typeset -g KAWAII_EMOJI=(
  '(๑˃̵ᴗ˂̵)و'
  '(๑•̀ㅂ•́)و'
  '(๑°ω°๑)و'
  '(๑•ㅂ•)و'
  '(๑ᵒᗜ ᵒ)و'
)


typeset -gA PROMPT_PALETTE=(
  host          '%b%F{157}'
  user          '%b%F{253}'
  path          '%B%F{229}'
  venv          '%b%F{081}'
  ssh.via       '%b%F{222}'
  ssh.agent     '%b%F{081}'
  time          '%b%F{247}'
  elapsed       '%b%F{222}'
  exit.mark     '%b%F{246}'
  exit.code     '%B%F{203}'
  git.commited  '%b%F{002}'
  git.staged    '%b%F{226}'
  git.modified  '%b%F{009}'
  git.untracked '%b%F{136}'
  conj          '%b%F{102}'
  typing        '%b%F{252}'
  normal        '%b%F{252}'
  success       '%b%F{013}'
  error         '%b%F{203}'
  reset         '%{\e[00m%}'
)


typeset -gA prompts=(
  margin     ""
  host       ""
  user       ""
  path       ""
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
  venv       0
  ssh.via    0
  ssh.agent  0
  git        0
  time       0
  elapsed    0
  exit       0
)


typeset -gi exec_timestamp=0


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
  prompts[host]="${PROMPT_PALETTE[normal]}[${PROMPT_PALETTE[host]}${name}${PROMPT_PALETTE[normal]}]"
  prompts_len[host]=$(( ${#name} + 2 ))
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


calc_path_length() {
  local current_path="$1"
  local total_chars=$(echo ${current_path} | LC_CTYPE=ja_JP.UTF-8 wc -m)
  local total_bytes=$(echo ${current_path} | LC_CTYPE=ja_JP.UTF-8 wc -c)
  local zenkaku_bytes=3
  local zenkaku_width=2
  local n_hankaku=$(( (zenkaku_bytes * total_chars - total_bytes ) / 2 ))
  local n_zenkaku=$(( (total_bytes - total_chars) / 2 ))
  echo $(( n_hankaku + zenkaku_width * n_zenkaku ))
}


set_current_path() {
  LC_CTYPE=ja_JP.UTF-8 local current_path=${(%):-%~}
  prompts[path]=" ${PROMPT_PALETTE[conj]}in ${PROMPT_PALETTE[path]}${current_path}"
  prompts_len[path]=$(( $(calc_path_length ${current_path}) + 4 ))
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
  [[ ${rawip} =~ '\.' ]] && echo "***.$(echo ${rawip} | awk -F'.' '{print $NF}')"
  [[ ${rawip} =~ ':' ]] && echo "****:$(echo ${rawip} | awk -F':' '{print $NF}')"
}


set_via_ssh_info() {
  local srcip=$(echo ${SSH_CLIENT} | awk '{print $1}')
  if [[ -n ${srcip} ]]; then
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
  local corner_top="${prompts[margin]}${PROMPT_PALETTE[normal]}${PROMPT_SYMBOL[corner.top]}"
  local corner_bottom="${PROMPT_PALETTE[reset]}${PROMPT_PALETTE[normal]}${PROMPT_SYMBOL[corner.bottom]}"
  local left_part="${corner_top}${prompts[host]}${prompts[path]}${prompts[git]}${prompts[ssh.agent]}${prompts[ssh.via]}"
  local right_part="${prompts[time]}${prompts[elapsed]}"
  local prompt_len=$(( prompts_len[host] + prompts_len[path] + prompts_len[git] + prompts_len[ssh.agent] + prompts_len[ssh.via] ))
  local prompt_len=$(( prompt_len + prompts_len[time] + prompts_len[elapsed] ))
  local padding="$(( width - prompt_len - 2))"
  if (( padding > 0 )); then
    echo "${left_part}${(r:${padding}:)""}${right_part}"
  else
    echo "${left_part}"
  fi
  echo "${corner_bottom}${prompts[venv]}${prompts[typing]} "
}


sub_prompt() {
  echo "${prompts[exit]}"
}


preexec() {
  set_exec_timestamp
}


precmd() {
  set_last_status  # must be loaded at first!
  set_margin
  set_hostname
  set_user
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
