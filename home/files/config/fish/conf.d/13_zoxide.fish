if not status is-interactive
    return
end

if not command -sq zoxide
    return
end

zoxide init fish --cmd z | source

# zoxide's built-in interactive picker renders a plain score/path list and
# previews with `ls`. Keep its matching database, but render the picker with
# the same Catppuccin-aware rows used by the other fzf helpers.
function zi --description 'Interactively jump to a directory tracked by zoxide'
    command -sq fzf
    or begin
        echo 'zi: fzf is not installed' >&2
        return 1
    end

    set -l config_home "$HOME/.config"
    set -q XDG_CONFIG_HOME; and set config_home "$XDG_CONFIG_HOME"
    set -l fzf_rows "$config_home/fish/lib/fzf_rows.py"
    set -l fish_shell (command -s fish)
    set -l preview "command python3 '$fzf_rows' preview-zoxide {1}"

    set -l destination (command zoxide query --list --score -- $argv 2>/dev/null |
        command python3 "$fzf_rows" zoxide |
        command env NO_COLOR= SHELL="$fish_shell" fzf \
            --ansi \
            --with-nth=2.. \
            --nth=2.. \
            --accept-nth=1 \
            --preview="$preview" \
            --preview-window='down,30%,sharp' |
        command python3 "$fzf_rows" decode-zoxide)

    test -n "$destination"; or return 1
    __zoxide_cd -- "$destination[1]"
end
