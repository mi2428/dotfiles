source $HOMEBREW_HOME/opt/fzf/shell/completion.zsh
source $HOMEBREW_HOME/opt/fzf/shell/key-bindings.zsh
export FZF_COMPLETION_TRIGGER='**'
export FZF_DEFAULT_COMMAND="fd"
export FZF_DEFAULT_OPTS='--reverse --height 60% --border --inline-info --preview-window=right:60%:wrap --color=fg:252,fg+:233,bg+:002,preview-fg:252,prompt:226,pointer:007,info:247,spinner:237,header:009,gutter:237,hl:220,hl+:231'
export FZF_COMPLETION_OPTS="${FZF_DEFAULT_OPTS}"
export FZF_TMUX=1
export FZF_TMUX_HEIGHT=20
export PATH="${PATH:+${PATH}:}/opt/homebrew/opt/fzf/bin"

# Use fd (https://github.com/sharkdp/fd) instead of the default find
# command for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
  fd --hidden --follow --exclude ".git,Dropbox" . "$1"
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fd --type d --hidden --follow --exclude ".git,Dropbox" . "$1"
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
