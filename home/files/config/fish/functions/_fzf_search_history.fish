function _fzf_search_history --description 'Search command history with a Catppuccin timestamp column.'
    if test -z "$fish_private_mode"
        builtin history merge
    end
    if not set --query fzf_history_time_format
        set -f fzf_history_time_format "%m-%d %H:%M:%S"
    end
    set -l config_home "$HOME/.config"
    set -q XDG_CONFIG_HOME; and set config_home "$XDG_CONFIG_HOME"
    set -l fzf_rows "$config_home/fish/lib/fzf_rows.py"
    set -l fish_shell (command -s fish)
    set -f time_prefix_regex '^.*? │ '
    set -f commands_selected (
        builtin history --null --show-time="$fzf_history_time_format │ " |
        command python3 "$fzf_rows" history-display |
        command env NO_COLOR= SHELL="$fish_shell" fzf --read0 --print0 --multi --scheme=history --prompt="History> " --query=(commandline) \
            --ansi \
            --preview="string replace --regex '$time_prefix_regex' '' -- {} | fish_indent --ansi" \
            --preview-window="bottom:3:wrap" $fzf_history_opts |
        string split0 | string replace --regex $time_prefix_regex ''
    )
    if test -n "$commands_selected"
        commandline --replace -- $commands_selected
    end
    commandline --function repaint
end
