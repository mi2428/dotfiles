if not status is-interactive
    return
end

if not command -sq starship
    return
end

set -gx STARSHIP_CONFIG $HOME/.config/starship/starship.toml

function starship_transient_prompt_func
    starship prompt $argv
end

function starship_transient_rprompt_func
end

starship init fish | source

if functions -q enable_transience
    enable_transience
else if functions -q __starship_transient_execute
    bind --user \r __starship_transient_execute
    bind --user -M insert \r __starship_transient_execute
end
