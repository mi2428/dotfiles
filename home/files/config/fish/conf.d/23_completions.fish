if not status is-interactive
    return
end

if command -sq kubectl
    kubectl completion fish | source
end

if command -sq granted
    if not test -f "$HOME/.config/fish/completions/granted.fish"
        granted completion -s fish >/dev/null 2>&1
    end

    if test -f "$HOME/.config/fish/completions/granted.fish"
        source "$HOME/.config/fish/completions/granted.fish"
    end
end

if command -sq aws_completer
    complete --command aws --no-files --arguments \
        '(begin
            set -l line (commandline)
            set -lx COMP_SHELL fish
            set -lx COMP_LINE $line
            set -lx COMP_POINT (string length -- $line)
            aws_completer 2>/dev/null | string trim --right
        end)'
end

function __dotfiles_terraform_commands
    command -sq terraform; or return 0

    terraform -help 2>/dev/null \
        | string match -r '^[[:space:]]{2}[[:alnum:]-]+' \
        | while read -l line
            string replace -r '\s+.*$' '' -- (string trim -- $line)
        end
end

if command -sq terraform
    complete --command terraform --no-files -n '__fish_use_subcommand' -a '(__dotfiles_terraform_commands)'
end

complete --command d --wraps docker
complete --command k --wraps kubectl
complete --command ldk --wraps lazydocker
complete --command tf --wraps terraform

function __dotfiles_tmux_session_completions
    for session_name in (__dotfiles_tmux_session_names)
        printf '%s\t%s\n' "$session_name" 'tmux session'
    end
end

function __dotfiles_herdr_session_completions
    herdr session list --json 2>/dev/null |
        jq -r '.sessions[]? | [.name, (if .running then "running Herdr session" else "stopped Herdr session" end)] | @tsv' 2>/dev/null
end

function __dotfiles_herdr_running_session_completions
    herdr session list --json 2>/dev/null |
        jq -r '.sessions[]? | select(.running) | [.name, "running Herdr session"] | @tsv' 2>/dev/null
end

function __dotfiles_session_shortcut_command_completions
    printf '%s\t%s\n' l 'List sessions'
    printf '%s\t%s\n' c 'Create a named session'
    printf '%s\t%s\n' n 'Add a work area to a session'
    printf '%s\t%s\n' d 'Delete a session'
end

function __dotfiles_session_shortcut_needs_delete_target
    set -l tokens (commandline -pxc)
    test (count $tokens) -eq 2; and contains -- $tokens[2] d delete
end

function __dotfiles_session_shortcut_needs_create_name
    set -l tokens (commandline -pxc)
    test (count $tokens) -eq 2; and contains -- $tokens[2] c create
end

function __dotfiles_session_shortcut_needs_new_path
    set -l tokens (commandline -pxc)
    test (count $tokens) -eq 2; and contains -- $tokens[2] n new
end

function __dotfiles_session_shortcut_needs_new_target
    set -l tokens (commandline -pxc)
    test (count $tokens) -eq 3; and contains -- $tokens[2] n new
end

complete --command :: --wraps tmux
complete --command :: --condition __fish_is_first_arg --no-files --arguments '(__dotfiles_session_shortcut_command_completions)'
complete --command :: --condition __fish_is_first_arg --no-files --arguments '(__dotfiles_tmux_session_completions)'
complete --command :: --condition __dotfiles_session_shortcut_needs_delete_target --no-files --arguments '(__dotfiles_tmux_session_completions)'
complete --command :: --condition __dotfiles_session_shortcut_needs_create_name --no-files
complete --command :: --condition __dotfiles_session_shortcut_needs_new_path --no-files --arguments '(__fish_complete_directories)'
complete --command :: --condition __dotfiles_session_shortcut_needs_new_target --no-files --arguments '(__dotfiles_tmux_session_completions)'
complete --command ::: --wraps herdr
complete --command ::: --condition __fish_is_first_arg --no-files --arguments '(__dotfiles_session_shortcut_command_completions)'
complete --command ::: --condition __fish_is_first_arg --no-files --arguments '(__dotfiles_herdr_session_completions)'
complete --command ::: --condition __dotfiles_session_shortcut_needs_delete_target --no-files --arguments '(__dotfiles_herdr_session_completions)'
complete --command ::: --condition __dotfiles_session_shortcut_needs_create_name --no-files
complete --command ::: --condition __dotfiles_session_shortcut_needs_new_path --no-files --arguments '(__fish_complete_directories)'
complete --command ::: --condition __dotfiles_session_shortcut_needs_new_target --no-files --arguments '(__dotfiles_herdr_running_session_completions)'
