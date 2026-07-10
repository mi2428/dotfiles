function __dotfiles_title_git_branch --description "Print current git branch for terminal titles"
    command git symbolic-ref --quiet --short HEAD 2>/dev/null
end

function fish_title --description "Set terminal title similar to the iTerm2 profile"
    set -l pwd_dir_length 0
    if set -q pure_shorten_window_title_current_directory_length
        set pwd_dir_length $pure_shorten_window_title_current_directory_length
    end

    set -l location (fish_prompt_pwd_dir_length=$pwd_dir_length prompt_pwd)
    set -l branch (__dotfiles_title_git_branch)
    if test -n "$branch"
        set location "$location [$branch]"
    end

    if set -q SSH_TTY
        set -l host (prompt_hostname)
        set location "$host:$location"
    end

    set -l current_command (status current-command 2>/dev/null; or echo fish)
    if test "$current_command" = fish
        echo $location
    else
        echo "$current_command - $location"
    end
end
