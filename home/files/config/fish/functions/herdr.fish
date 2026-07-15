function herdr --wraps herdr --description "Run Herdr against the managed ~/.config tree"
    set -l managed_config_home "$HOME/.config"
    set -l managed_config "$managed_config_home/herdr/config.toml"

    if not set -q XDG_CONFIG_HOME; or test "$XDG_CONFIG_HOME" = "$managed_config_home"; or not test -f "$managed_config"
        command herdr $argv
        return $status
    end

    env \
        XDG_CONFIG_HOME="$managed_config_home" \
        HERDR_CONFIG_PATH="$managed_config" \
        command herdr $argv
end
