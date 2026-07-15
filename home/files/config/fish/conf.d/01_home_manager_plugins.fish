if test "$__fish_config_dir" = "$HOME/.config/fish"
    return
end

set -l home_manager_conf_dir "$HOME/.config/fish/conf.d"
if not test -d "$home_manager_conf_dir"
    return
end

# When XDG_CONFIG_HOME points at the repo checkout, fish skips the
# Home Manager-generated plugin loader shims under ~/.config/fish/conf.d.
for plugin_loader in "$home_manager_conf_dir"/plugin-*.fish
    if test -f "$plugin_loader"
        source "$plugin_loader"
    end
end
