function f
    set -l target .
    if test (count $argv) -gt 0
        set target $argv[1]
    end
    open -a Finder -- "$target"
end

function gty --description 'Open or resize Ghostty Herdr workspaces'
    if test (count $argv) -eq 0
        command ghostty.scpt
        return $status
    end

    if test (count $argv) -eq 1
        switch "$argv[1]"
            case -h --help
                printf '%s\n' \
                    'Usage:' \
                    '  gty' \
                    '  gty SESSION' \
                    '  gty r' \
                    '' \
                    'Open a Ghostty window with Herdr on the left and tmux on the right.' \
                    'Without SESSION, use the default Herdr session and unnamed tmux session.' \
                    'With SESSION, use that name for both Herdr and tmux.' \
                    'Use r to resize Herdr panes in every Ghostty window.'
                return 0
            case r
                command ghostty-resize-herdr-pane.scpt
                return $status
            case '-*'
                printf 'gty: unknown option: %s\n' "$argv[1]" >&2
                return 2
            case '*'
                command ghostty.scpt "$argv[1]"
                return $status
        end
    end

    echo 'Usage: gty [SESSION|r]' >&2
    return 2
end

if command -sq arch
    function x64
        exec arch -arch x86_64 fish --login
    end

    function a64
        exec arch -arch arm64e fish --login
    end
end

alias preview='open -a Preview'
alias skim='open -a Skim'
alias updatedb='/usr/libexec/locate.updatedb'
alias wireshark='open -n /Applications/Wireshark.app'

function update-aws-session-token
    sesstok (op item get soracom-aws-organization-jp --otp) -s -p $argv
end

function tamausi
    figlet tamasui | cowsay -n -d
end
