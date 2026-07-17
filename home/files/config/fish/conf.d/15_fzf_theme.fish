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

# fzf.fish routes its widgets through _fzf_wrapper.  Preserve its implementation
# while making only fzf children ignore an inherited NO_COLOR=1, which otherwise
# strips ANSI colours from candidate rows even though the Catppuccin UI remains
# coloured.
if functions -q _fzf_wrapper; and not functions -q __dotfiles_fzf_plugin_wrapper
    functions -c _fzf_wrapper __dotfiles_fzf_plugin_wrapper
end

if functions -q __dotfiles_fzf_plugin_wrapper
    function _fzf_wrapper
        set -lx NO_COLOR ''
        __dotfiles_fzf_plugin_wrapper $argv
    end
end

# fzf-git is sourced before this file when it is installed.  Wrap its dispatcher
# for the same local NO_COLOR handling without changing the external plugin.
if functions -q __fzf_git_sh; and not functions -q __dotfiles_fzf_git_dispatcher
    functions -c __fzf_git_sh __dotfiles_fzf_git_dispatcher
end

if functions -q __dotfiles_fzf_git_dispatcher
    function __fzf_git_sh
        set -lx NO_COLOR ''
        __dotfiles_fzf_git_dispatcher $argv
    end
end
