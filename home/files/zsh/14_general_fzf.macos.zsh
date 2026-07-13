if whence -p fzf >/dev/null && fzf --zsh >/dev/null 2>&1; then
  source <(fzf --zsh) 2>/dev/null
fi
export FZF_COMPLETION_TRIGGER='**'
if whence -p fd 1> /dev/null; then
  export FZF_FD_BIN='fd'
  export FZF_DEFAULT_COMMAND='fd --hidden --follow --exclude .git --exclude Dropbox'
elif whence -p fdfind 1> /dev/null; then
  export FZF_FD_BIN='fdfind'
  export FZF_DEFAULT_COMMAND='fdfind --hidden --follow --exclude .git --exclude Dropbox'
else
  export FZF_FD_BIN=''
  export FZF_DEFAULT_COMMAND='find . -mindepth 1'
fi
export FZF_DEFAULT_OPTS="--reverse --height 60% --border --inline-info --preview-window=right:60%:wrap --color=bg:-1,bg+:-1,fg:${CTP_TEXT},fg+:${CTP_ROSEWATER},hl:${CTP_BLUE},hl+:${CTP_LAVENDER},border:${CTP_OVERLAY1},gutter:-1,info:${CTP_OVERLAY0},prompt:${CTP_MAUVE},pointer:${CTP_PEACH},spinner:${CTP_SKY},header:${CTP_TEAL}"
export FZF_COMPLETION_OPTS="${FZF_DEFAULT_OPTS}"
export FZF_TMUX=1
export FZF_TMUX_HEIGHT=20

# Use fd (https://github.com/sharkdp/fd) instead of the default find
# command for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
  if [[ -n $FZF_FD_BIN ]]; then
    $FZF_FD_BIN --hidden --follow --exclude .git --exclude Dropbox . "$1"
  else
    command find "$1" -mindepth 1 \
      \( -path '*/.git' -o -path '*/.git/*' -o -path '*/Dropbox' -o -path '*/Dropbox/*' \) -prune -o -print
  fi
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  if [[ -n $FZF_FD_BIN ]]; then
    $FZF_FD_BIN --type d --hidden --follow --exclude .git --exclude Dropbox . "$1"
  else
    command find "$1" -type d \
      \( -path '*/.git' -o -path '*/.git/*' -o -path '*/Dropbox' -o -path '*/Dropbox/*' \) -prune -o -print
  fi
}

# (EXPERIMENTAL) Advanced customization of fzf options via _fzf_comprun function
# - The first argument to the function is the name of the command.
# - You should make sure to pass the rest of the arguments to fzf.
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
    cd|pushd)     fzf "$@" --preview 'tree -L 3 -C {} | head -200' ;;
    vi|vim|nvim)  fzf "$@" --preview '[[ $(file --mime {}) =~ directory ]] \
                                      && tree -L 3 -C {} | head -200 \
                                      || bat --style=numbers --color=always --line-range :500 {}' ;;
    cot|code)     fzf "$@" --preview '[[ $(file --mime {}) =~ directory ]] \
                                      && tree -L 3 -C {} | head -200 \
                                      || bat --style=numbers --color=always --line-range :500 {}' ;;
    export|unset) fzf "$@" --preview "eval 'echo \$'{}" ;;
    ssh)          fzf "$@" --preview 'curl -s http://ip-api.com/json/{} | jq . | bat -l json --color=always' ;;
    *)            fzf "$@" ;;
  esac
}
