function fish_user_key_bindings
    fish_default_key_bindings

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
