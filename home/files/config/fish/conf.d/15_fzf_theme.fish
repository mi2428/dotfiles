if not status is-interactive
    return
end

if not command -sq fzf
    return
end

set -l fzf_theme "catppuccin-fzf-$DOTFILES_CATPPUCCIN_FLAVOUR.rc"
set -l fzf_theme_file "$HOME/.config/fzf/themes/$fzf_theme"
set -l source_file (path resolve (status filename))
set -l etc_root (path dirname (path dirname (path dirname $source_file)))
if not test -f "$fzf_theme_file"
    set fzf_theme_file "$etc_root/fzf/themes/$fzf_theme"
end

if test -f "$fzf_theme_file"
    set -gx FZF_DEFAULT_OPTS_FILE "$fzf_theme_file"
else
    set -e FZF_DEFAULT_OPTS_FILE
end

set -gx FZF_DEFAULT_OPTS "\
--height=60% \
--layout=reverse \
--border \
--style=full \
--info=inline-right \
--preview-window=right,55%,border-left \
--bind='ctrl-/:change-preview-window(right,55%,border-left|down,60%,border-top|hidden)' \
--color=bg:-1"
