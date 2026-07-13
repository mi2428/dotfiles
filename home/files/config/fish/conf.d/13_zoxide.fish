if not status is-interactive
    return
end

if not command -sq zoxide
    return
end

zoxide init fish --cmd z | source
