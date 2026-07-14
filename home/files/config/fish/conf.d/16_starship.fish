if not status is-interactive
    return
end

if not command -sq starship
    return
end

set -l starship_config_root "$HOME/.config"
if set -q XDG_CONFIG_HOME
    set starship_config_root "$XDG_CONFIG_HOME"
end

set -gx STARSHIP_CONFIG "$starship_config_root/starship/starship.toml"

function starship_transient_prompt_func
    starship prompt $argv
end

function starship_transient_rprompt_func
end

starship init fish | source

# Fish 4.x has built-in transient prompts, but in this setup the built-in
# final-rendering path is not actually collapsing old prompts. Force the
# Starship repaint-based transient flow instead.
set -g fish_transient_prompt 0
bind --user \r __starship_transient_execute
bind --user -M insert \r __starship_transient_execute
