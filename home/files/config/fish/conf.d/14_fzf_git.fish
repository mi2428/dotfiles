if not status is-interactive
    return
end

if not command -sq fzf
    return
end

set -l fzf_git_home "$HOME/.local/share"
if set -q XDG_DATA_HOME
    set fzf_git_home "$XDG_DATA_HOME"
end

set -l fzf_git_dir "$fzf_git_home/fzf-git"
set -l fzf_git_script "$fzf_git_dir/fzf-git.fish"

if test -f "$fzf_git_script"
    source "$fzf_git_script"
end
