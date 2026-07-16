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
