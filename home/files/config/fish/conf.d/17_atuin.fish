if not status is-interactive
    return
end

if not command -sq atuin
    return
end

# Keep ctrl-r on fzf.fish, keep the Up Arrow on fish's default history
# navigation, and call Atuin only through an explicit custom binding. Atuin's
# fish init exposes `_atuin_search`, so we reuse that widget instead of
# reimplementing the shell integration ourselves.
# References:
# - https://github.com/atuinsh/atuin/blob/main/crates/atuin/src/shell/atuin.fish
atuin init fish --disable-ctrl-r --disable-up-arrow | source

function __dotfiles_atuin_search
    functions -q _atuin_search; or return 1
    _atuin_search
end
