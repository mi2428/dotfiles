if not status is-interactive
    return
end

if not command -sq starship
    return
end

set -gx STARSHIP_CONFIG $HOME/.config/starship/starship.toml

function starship_transient_prompt_func
    starship module character
end

starship init fish | source
enable_transience
