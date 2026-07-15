for stale_abbr in Ia Iag Ic Ieg Ig Igr Ih Ik Im Ip Is It Iv Iw Ix
    abbr --erase -- $stale_abbr 2>/dev/null
end

abbr --add -- gcan 'git commit --amend --no-edit'
abbr --add -- gcaa 'git commit --amend'
abbr --add -- gpf 'git push --force-with-lease'
abbr --add -- gclean 'git clean -fd'
abbr --add -- gri 'git rebase -i'
abbr --add -- glg 'git log --oneline --graph --decorate --all'
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
alias n='notes'
alias o='open'
alias r='rm -i'
alias s='sudo'
alias v='vim -R'
alias x='chmod +x'
alias y='yes'
alias an='ansible'
alias be='bundle exec'
alias bi='bundle install'
alias bu='bundle update'
alias dc='docker compose'
alias ga='git add'
alias gb='git branch'
alias gc='git commit -s -m'

function __git_delta_lazygit
    set -l paging never
    set -l added_label (printf '\033[1;38;2;166;227;161mA\033[0m')
    set -l copied_label (printf '\033[1;38;2;148;226;213mC\033[0m')
    set -l modified_label (printf '\033[1;38;2;249;226;175mM\033[0m')
    set -l removed_label (printf '\033[1;38;2;243;139;168mD\033[0m')
    set -l renamed_label (printf '\033[1;38;2;137;180;250mR\033[0m')
    set -l delta_args \
        --features=catppuccin-mocha \
        --dark \
        "--file-added-label=$added_label" \
        "--file-copied-label=$copied_label" \
        "--file-modified-label=$modified_label" \
        "--file-removed-label=$removed_label" \
        "--file-renamed-label=$renamed_label" \
        --line-numbers \
        --side-by-side

    if test -t 1
        set paging always
        # Repaint from the top on half-page jumps to reduce visual artifacts in tmux.
        set -a delta_args --pager 'less -Rc'
    end

    if not set -q TMUX
        set -a delta_args --hyperlinks '--hyperlinks-file-link-format=lazygit-edit://{path}:{line}'
    end

    delta --paging="$paging" $delta_args
end

function gd
    git-delta-input -- $argv | __git_delta_lazygit
    return $pipestatus[1]
end

function __dotfiles_git_handler_name --argument-names subcmd
    string replace -a '-' '_' -- "__dotfiles_git_subcommand_$subcmd"
end

function __dotfiles_git_subcommand_b
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

function gdd
    set -l base_ref

    if git rev-parse --verify --quiet refs/remotes/origin/HEAD >/dev/null 2>/dev/null
        set base_ref origin/HEAD
    else if git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>/dev/null
        set base_ref origin/main
    else if git rev-parse --verify --quiet refs/remotes/origin/master >/dev/null 2>/dev/null
        set base_ref origin/master
    else
        echo 'gdd: could not determine a default base ref (tried origin/HEAD, origin/main, origin/master)' >&2
        return 1
    end

    git-delta-input --range "$base_ref"...HEAD -- $argv | __git_delta_lazygit
    return $pipestatus[1]
end

alias gf='git fetch'
alias gp='git push'
alias gs='git status'
alias kc='kubectl'
alias py='python3'
alias rc='bundle exec rails c'
alias tf='terraform'
alias gbm='git branch -M'
alias gco='git checkout'
alias gdc='git diff --cached'
alias gpl='git pull'
alias gwa='git worktree add'
alias gwr='git worktree remove'
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
    set -l name (docker ps --format '{{.Names}}' | fzf)
    test -n "$name"; and docker exec -it "$name" $argv
end

function gaa
    git add -A $argv
end

function gac
    git add -A; and git commit -s -m (string join ' ' -- $argv)
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

if command -sq htop
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
