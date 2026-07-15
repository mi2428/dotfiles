function herdr --wraps herdr --description "Keep Herdr runtime files out of the tracked repo config tree"
    set -l managed_config_home "$HOME/.config"
    set -l managed_config "$managed_config_home/herdr/config.toml"
    set -l source_file (path resolve (status filename))
    set -l source_config_root (path dirname (path dirname (path dirname $source_file)))

    if not set -q XDG_CONFIG_HOME; or test "$XDG_CONFIG_HOME" = "$managed_config_home"; or not test -f "$managed_config"
        command herdr $argv
        return $status
    end

    if test "$XDG_CONFIG_HOME" != "$source_config_root"
        command herdr $argv
        return $status
    end

    env \
        XDG_CONFIG_HOME="$managed_config_home" \
        HERDR_CONFIG_PATH="$managed_config" \
        command herdr $argv
end
