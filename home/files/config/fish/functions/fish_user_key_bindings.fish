function fish_user_key_bindings
    fish_default_key_bindings

    # fzf.fish puts its variable browser on Ctrl+V, shadowing clipboard paste.
    # Move it to Ctrl+Alt+V and keep Ctrl+V as paste; herdr-app receives
    # Omarchy's Super+V as Ctrl+V because the window is not tagged terminal.
    if functions -q fzf_configure_bindings
        fzf_configure_bindings --variables=ctrl-alt-v
    end
    if functions -q fish_clipboard_paste
        bind \cv fish_clipboard_paste
        bind -M insert \cv fish_clipboard_paste
    end

    bind \co 'commandline -f accept-autosuggestion'
    bind \e0 _severity_clear
    bind \e1 _severity_level1
    bind \e2 _severity_level2
    bind \e3 _severity_level3
    bind \e4 _severity_level4
    bind \es _toggle_ssh_prompt
    bind \eh _sanitize_history
    bind alt-r __dotfiles_atuin_search
end
