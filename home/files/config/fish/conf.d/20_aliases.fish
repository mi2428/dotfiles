set -l __dotfiles_git_ui_helper_file "$__fish_config_dir/lib/dotfiles_git_ui_helpers.fish"
if test -f "$__dotfiles_git_ui_helper_file"
    source "$__dotfiles_git_ui_helper_file"
end
set -e __dotfiles_git_ui_helper_file

for stale_abbr in Ia Iag Ic Ieg Ig Igr Ih Ik Im Ip Is It Iv Iw Ix
    abbr --erase -- $stale_abbr 2>/dev/null
end

abbr --add -- dcu 'docker compose up'
abbr --add -- dcub 'docker compose up --build'
abbr --add -- dce 'docker compose exec'
abbr --add -- kgp 'kubectl get pods'
abbr --add -- kgs 'kubectl get svc'
abbr --add -- kgd 'kubectl get deploy'

alias :q='exit'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ..2='cd ../..'
alias ..3='cd ../../..'
alias ..4='cd ../../../..'
alias ..5='cd ../../../../..'

alias b='bat'
alias c='pbcopy'
alias d='docker'
alias ef='exec fish'
alias k='kubectl'
alias n='notes'
alias o='open'
alias r='rm -i'
alias s='sudo'
alias x='chmod +x'
alias y='yes'

alias an='ansible'
alias be='bundle exec'
alias bi='bundle install'
alias bu='bundle update'
alias ga='g a'
alias gb='g b'
alias gc='g c'
alias gd='g d'
alias gf='g f'
alias gp='g p'
alias gs='g s'

alias gdd='g dd'
alias gpl='g pl'
alias ldk='lazydocker'

function __git_delta_lazygit
    __dotfiles_git_ui_delta_lazygit
end

function __dotfiles_git_handler_name --argument-names subcmd
    string replace -a - _ -- "__dotfiles_git_subcommand_$subcmd"
end

function __dotfiles_git_subcommand_a
    command git add $argv
end

function __dotfiles_git_subcommand_aa
    command git add -A $argv
end

function __dotfiles_git_subcommand_ac
    command git add -A
    and command git commit -s -m (string join ' ' -- $argv)
end

function __dotfiles_git_subcommand_c
    command git commit -s -m $argv
end

function __dotfiles_git_subcommand_can
    command git commit --amend --no-edit $argv
end

function __dotfiles_git_subcommand_caa
    command git commit --amend $argv
end

function __dotfiles_git_subcommand_d
    git-delta-input -- $argv | __git_delta_lazygit
    return $pipestatus[1]
end

function __dotfiles_git_subcommand_dd
    set -l base_ref

    if git rev-parse --verify --quiet refs/remotes/origin/HEAD >/dev/null 2>/dev/null
        set base_ref origin/HEAD
    else if git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>/dev/null
        set base_ref origin/main
    else if git rev-parse --verify --quiet refs/remotes/origin/master >/dev/null 2>/dev/null
        set base_ref origin/master
    else
        echo 'g dd: could not determine a default base ref (tried origin/HEAD, origin/main, origin/master)' >&2
        return 1
    end

    git-delta-input --range "$base_ref"...HEAD -- $argv | __git_delta_lazygit
    return $pipestatus[1]
end

function __dotfiles_git_subcommand_f
    command git fetch $argv
end

function __dotfiles_git_subcommand_p
    command git push $argv
end

function __dotfiles_git_subcommand_pf
    command git push --force-with-lease $argv
end

function __dotfiles_git_subcommand_s
    command git status $argv
end

function __dotfiles_git_subcommand_b
    if test (count $argv) -eq 1 && test "$argv[1]" = -D
        command git-b -D
        return $status
    end

    if test (count $argv) -ge 1; and contains -- "$argv[1]" -w --worktree
        set -l args $argv[2..-1]
        set -l create 0
        set -l branch ''
        set -l start_ref ''

        while test (count $args) -gt 0
            switch "$args[1]"
                case -c --create
                    set create 1
                case --from
                    set args $args[2..-1]
                    test (count $args) -gt 0; or begin
                        printf 'g b: --from requires a ref\n' >&2
                        return 2
                    end
                    set start_ref "$args[1]"
                case --
                    set args $args[2..-1]
                    if test (count $args) -gt 0
                        test -z "$branch"; and test (count $args) -eq 1; or begin
                            printf 'g b: expected one branch\n' >&2
                            return 2
                        end
                        set branch "$args[1]"
                    end
                    break
                case '-*'
                    printf 'g b: unknown worktree option: %s\n' "$args[1]" >&2
                    return 2
                case '*'
                    test -z "$branch"; or begin
                        printf 'g b: expected one branch\n' >&2
                        return 2
                    end
                    set branch "$args[1]"
            end
            set args $args[2..-1]
        end

        set -l result
        if test $create -eq 1
            test -n "$branch"; or begin
                printf 'g b: -c requires a branch\n' >&2
                return 2
            end
            set result (command git-b __create-worktree "$branch" "$start_ref")
        else
            test -z "$start_ref"; or begin
                printf 'g b: --from requires -c\n' >&2
                return 2
            end
            set result (command git-b __resolve-worktree "$branch")
        end
        set -l status_code $status
        test $status_code -eq 0; or return $status_code

        set -l parts (string split \t -- "$result")
        test "$parts[1]" = cd; and test -n "$parts[2]"; or begin
            printf 'g b: invalid worktree action\n' >&2
            return 1
        end
        builtin cd -- "$parts[2]"
        and __dotfiles_list_dir
        return $status
    end

    if test (count $argv) -gt 0
        command git branch $argv
        return $status
    end

    set -l result (command git-b __resolve-action)
    set -l status_code $status
    test $status_code -eq 0
    or return $status_code

    set -l parts (string split \t -- $result)
    switch $parts[1]
        case cd
            builtin cd -- $parts[2]
            and __dotfiles_list_dir
        case switch
            command git switch -- $parts[2]
        case track
            command git switch --track -c $parts[2] $parts[3]
        case '*'
            printf 'g b: unknown action: %s\n' "$parts[1]" >&2
            return 1
    end
end

function __dotfiles_git_subcommand_bm
    command git branch -M $argv
end

function __dotfiles_git_subcommand_co
    command git checkout $argv
end

function __dotfiles_git_subcommand_dc
    command git diff --cached $argv
end

function __dotfiles_git_subcommand_pl
    command git pull $argv
end

function __dotfiles_git_subcommand_wa
    command git worktree add $argv
end

function __dotfiles_git_subcommand_wr
    command git worktree remove $argv
end

function __dotfiles_git_subcommand_clean
    command git clean -fd $argv
end

function __dotfiles_git_subcommand_ri
    command git rebase -i $argv
end

function __dotfiles_git_subcommand_lg
    command git log --oneline --graph --decorate --all $argv
end

function g
    if test (count $argv) -eq 0
        command git
        return $status
    end

    set -l subcmd $argv[1]
    set -l handler (__dotfiles_git_handler_name $subcmd)
    set -l rest $argv[2..-1]

    if functions -q $handler
        $handler $rest
    else
        command git $argv
    end
end

function __dotfiles_command_words --argument-names command_text fallback
    if test -n "$command_text"
        string split ' ' -- "$command_text"
    else
        printf '%s\n' "$fallback"
    end
end

function Ia
    awk $argv
end

function Iag
    agrep $argv
end

function Ic
    pbcopy $argv
end

function Ieg
    egrep $argv
end

function Ig
    grep $argv
end

function Igr
    groff -s -p -t -e -Tlatin1 -mandoc $argv
end

function Ih
    head $argv
end

function Ik
    keep $argv
end

function Im
    more $argv
end

function Ip
    set -l pager_cmd (__dotfiles_command_words "$PAGER" less)
    command $pager_cmd $argv
end

function Is
    sort $argv
end

function It
    tail $argv
end

function Iv
    set -l editor_cmd (__dotfiles_command_words "$EDITOR" vi)
    command $editor_cmd $argv
end

function Iw
    wc $argv
end

function Ix
    xargs $argv
end

alias py='python3'
alias rc='bundle exec rails c'
alias tf='terraform'
alias ipf='iperf3'
alias ipp='ip -6'
alias ipy='ipython3'
alias mkd='mkdir -p'
alias egrep='egrep -n --color=auto'
alias fgrep='fgrep -n --color=auto'
alias free='free -h'
alias grep='grep -n --color=auto'
alias httpserver='python3 -m http.server'
alias less='less --no-init --quit-if-one-screen'

function tig
    if command -sq lazygit
        lazygit $argv
    else
        command tig $argv
    end
end

function zl
    exec env PROMPT_SEVERITY="$PROMPT_SEVERITY" OUTSIDE_HOSTNAME="$OUTSIDE_HOSTNAME" fish --login
end

function dck
    docker compose kill; and docker compose rm -f
end

function dcl
    docker compose logs -f $argv
end

function dcp
    docker compose ps -a $argv
end

function dow
    cd "$HOME/Downloads"
end

function dox
    set -l config_home "$HOME/.config"
    set -q XDG_CONFIG_HOME; and set config_home "$XDG_CONFIG_HOME"
    set -l fzf_rows "$config_home/fish/lib/fzf_rows.py"
    set -l fish_shell (command -s fish)
    set -l name (docker ps --format '{{.Names}}' |
        command python3 "$fzf_rows" simple |
        command env NO_COLOR= SHELL="$fish_shell" fzf --ansi --with-nth=2.. --nth=2.. --accept-nth=1 |
        command python3 "$fzf_rows" decode)
    test -n "$name"; and docker exec -it "$name" $argv
end

function ssa
    ssh-agent fish
end

function dcrm
    docker compose rm -f $argv
end

function dcup
    docker compose up -d $argv; and docker compose logs -f
end

function dorm
    set -l ids (docker ps -qa)
    test -n "$ids"; and docker rm $ids 2>/dev/null
end

function dormi
    set -l ids (docker images --filter 'dangling=true' -q)
    test -n "$ids"; and docker rmi $ids 2>/dev/null
end

function editssh
    set -l editor_cmd (__dotfiles_command_words "$EDITOR" vi)
    $editor_cmd "$HOME/.ssh/config"
end

function myip
    curl -s https://ipinfo.io | jq
end

alias sshh='sshuttle'

if command -sq iperf3-rs
    alias iperf3='iperf3-rs'
end

if command -sq clockping
    alias cping='clockping'
end

if command -sq eza
    alias l='__dotfiles_eza --icons=auto --group-directories-first --hyperlink=auto'
    alias ls='__dotfiles_eza --icons=auto --group-directories-first --hyperlink=auto'
    alias ll='__dotfiles_eza -l --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto'
    alias la='__dotfiles_eza -l -arbghi --git --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto'
    alias lr='__dotfiles_eza -lR -arbghi --git --git-ignore --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto -I ".git|__pycache__"'
    alias lt='__dotfiles_eza -lT -arbghi --git --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto -I ".git|__pycache__|.terraform"'
    alias laa='__dotfiles_eza -l -arbghi@ --git --icons=auto --group-directories-first --header --time-style=relative --hyperlink=auto'
else if command -sq exa
    alias l='exa --icons'
    alias ls='exa --icons'
    alias ll='exa -l --icons'
    alias la='exa -l -arbghi --git --icons'
    alias lr='exa -lR -arbghi --git -I ".git|__pycache__" --icons'
    alias lt='exa -lT -arbghi --git -I ".git|__pycache__|.terraform" --icons'
    alias laa='exa -l -arbghi@ --git --icons'
else
    alias l='ls --color=auto'
    alias ls='ls --color=auto'
    alias ll='ls --color=auto -alF'
    alias la='ls --color=auto -A'
end

if command -sq btop
    alias top='btop'
else if command -sq htop
    alias top='htop'
end

if command -sq vim
    set -gx EDITOR vim
    alias vi='vim'
end

if command -sq nvim
    set -gx EDITOR nvim
    alias vi='nvim'
    alias vim='nvim'
    alias emacs='nvim'
    alias nano='nvim'
    alias pico='nvim'
    alias mg='nvim'
end

if command -sq code
    alias edit='code'
    alias atom='code'
end

if command -sq tldr
    alias h='tldr'
else
    alias h='man'
end
