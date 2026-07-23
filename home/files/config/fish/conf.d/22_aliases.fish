function f
    set -l target .
    if test (count $argv) -gt 0
        set target $argv[1]
    end
    open -a Finder -- "$target"
end

function gty --description 'Open or resize the Ghostty Herdr workspace'
    if test (count $argv) -eq 0
        command ghostty.scpt
        return $status
    end

    if test (count $argv) -eq 1 -a "$argv[1]" = r
        command ghostty-resize-herdr-pane.scpt
        return $status
    end

    echo 'Usage: gty [r]' >&2
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
