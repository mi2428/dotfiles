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
complete --command ::: --wraps herdr
complete --command ::: --short-option n --long-option new-workspace --require-parameter --no-files --arguments '(__fish_complete_directories)' --description 'Create and focus a workspace in the running Herdr server'
