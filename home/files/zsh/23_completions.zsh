_dotfiles_enable_bash_completion() {
  if [[ -n ${DOTFILES_BASHCOMPINIT_READY:-} ]]; then
    return 0
  fi

  autoload -Uz bashcompinit
  bashcompinit
  export DOTFILES_BASHCOMPINIT_READY=1
}

_dotfiles_source_granted_zsh_completion() {
  local granted_root assume_dir granted_dir

  granted_root="$HOME/.granted/zsh_autocomplete"
  assume_dir="$granted_root/assume"
  granted_dir="$granted_root/granted"

  if [[ ! -r "$assume_dir/_assume" || ! -r "$granted_dir/_granted" ]]; then
    granted completion -s zsh >/dev/null 2>&1 || return 1
  fi

  [[ -d "$assume_dir" ]] && fpath=("$assume_dir" $fpath)
  [[ -d "$granted_dir" ]] && fpath=("$granted_dir" $fpath)
  (( $+functions[_assume] )) || autoload -Uz _assume
  (( $+functions[_granted] )) || autoload -Uz _granted
  (( $+functions[_assume] )) && compdef _assume assume
  (( $+functions[_granted] )) && compdef _granted granted
}

if (( ${+commands[kubectl]} )); then
  source <(kubectl completion zsh)
fi

if (( ${+commands[granted]} )); then
  _dotfiles_source_granted_zsh_completion
fi

if (( ${+commands[aws_completer]} )); then
  _dotfiles_enable_bash_completion
  complete -C "$(whence -p aws_completer)" aws
fi

if (( ${+commands[terraform]} )); then
  _dotfiles_enable_bash_completion
  complete -o nospace -C "$(whence -p terraform)" terraform
fi

(( ${+functions[_docker]} )) && compdef _docker d
(( ${+commands[kubectl]} )) && compdef k=kubectl
(( ${+functions[_lazydocker]} )) && compdef _lazydocker ldk
(( ${+commands[terraform]} )) && compdef tf=terraform

_dotfiles_tmux_session_shortcut() {
  local original_command
  local -a session_names session_commands

  if (( CURRENT == 3 )) && [[ "$words[2]" == d || "$words[2]" == delete ]]; then
    session_names=("${(@f)$(__dotfiles_tmux_session_names)}")
    (( ${#session_names} > 0 )) && compadd -X 'tmux sessions' -- "$session_names[@]"
    return
  elif (( CURRENT == 4 )) && [[ "$words[2]" == n || "$words[2]" == new ]]; then
    session_names=("${(@f)$(__dotfiles_tmux_session_names)}")
    (( ${#session_names} > 0 )) && compadd -X 'tmux sessions' -- "$session_names[@]"
    return
  elif (( CURRENT == 3 )) && [[ "$words[2]" == c || "$words[2]" == create ]]; then
    _message 'session name'
    return
  elif (( CURRENT == 3 )) && [[ "$words[2]" == n || "$words[2]" == new ]]; then
    _directories
    return
  fi

  if (( CURRENT == 2 )); then
    session_commands=(
      'l:list sessions'
      'c:create a named session'
      'n:add a work area to a session'
      'd:delete a session'
    )
    _describe -t commands 'session commands' session_commands
    session_names=("${(@f)$(__dotfiles_tmux_session_names)}")
    (( ${#session_names} > 0 )) && compadd -X 'tmux sessions' -- "$session_names[@]"
  fi

  if (( ${+functions[_tmux]} )); then
    original_command="$words[1]"
    words[1]=tmux
    _tmux
    words[1]="$original_command"
  fi
}

_dotfiles_herdr_session_shortcut() {
  local original_command
  local -a sessions session_commands

  if (( CURRENT == 3 )) && [[ "$words[2]" == d || "$words[2]" == delete ]]; then
    sessions=("${(@f)$(command herdr session list --json 2>/dev/null | jq -r '.sessions[]? | "\(.name):\(if .running then "running" else "stopped" end)"' 2>/dev/null)}")
    (( ${#sessions} > 0 )) && _describe -t sessions 'Herdr sessions' sessions
    return
  elif (( CURRENT == 4 )) && [[ "$words[2]" == n || "$words[2]" == new ]]; then
    sessions=("${(@f)$(command herdr session list --json 2>/dev/null | jq -r '.sessions[]? | select(.running) | "\(.name):running"' 2>/dev/null)}")
    (( ${#sessions} > 0 )) && _describe -t sessions 'running Herdr sessions' sessions
    return
  elif (( CURRENT == 3 )) && [[ "$words[2]" == c || "$words[2]" == create ]]; then
    _message 'session name'
    return
  elif (( CURRENT == 3 )) && [[ "$words[2]" == n || "$words[2]" == new ]]; then
    _directories
    return
  fi

  if (( CURRENT == 2 )); then
    session_commands=(
      'l:list sessions'
      'c:create a named session'
      'n:add a work area to a session'
      'd:delete a session'
    )
    _describe -t commands 'session commands' session_commands
    sessions=("${(@f)$(command herdr session list --json 2>/dev/null | jq -r '.sessions[]? | "\(.name):\(if .running then "running" else "stopped" end)"' 2>/dev/null)}")
    (( ${#sessions} > 0 )) && _describe -t sessions 'Herdr sessions' sessions
  fi

  if (( ${+functions[_herdr]} )); then
    original_command="$words[1]"
    words[1]=herdr
    _herdr
    words[1]="$original_command"
  fi
}

compdef _dotfiles_tmux_session_shortcut ::
compdef _dotfiles_herdr_session_shortcut :::
