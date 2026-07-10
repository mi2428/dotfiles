abbr --add --position anywhere -- Ia '| awk'
abbr --add --position anywhere -- Iag '| agrep'
abbr --add --position anywhere -- Ic '| pbcopy'
abbr --add --position anywhere -- Ieg '| egrep'
abbr --add --position anywhere -- Ig '| grep'
abbr --add --position anywhere -- Igr 'groff -s -p -t -e -Tlatin1 -mandoc'
abbr --add --position anywhere -- Ih '| head'
abbr --add --position anywhere -- Ik '| keep'
abbr --add --position anywhere -- Im '| more'
abbr --add --position anywhere -- Ip '| $PAGER'
abbr --add --position anywhere -- Is '| sort'
abbr --add --position anywhere -- It '| tail'
abbr --add --position anywhere -- Iv '| $EDITOR'
abbr --add --position anywhere -- Iw '| wc'
abbr --add --position anywhere -- Ix '| xargs'

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
alias g='git'
alias j='jmp'
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
alias gd='git diff'
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
alias jmp='goto'
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

function z
    exec env PROMPT_SEVERITY=$PROMPT_SEVERITY OUTSIDE_HOSTNAME=$OUTSIDE_HOSTNAME fish --login
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
    cd $HOME/Downloads
end

function dox
    set -l name (docker ps --format '{{.Names}}' | fzf)
    test -n "$name"; and docker exec -it $name $argv
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
    $EDITOR $HOME/.ssh/config
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
    alias l='eza --icons=auto'
    alias ls='eza --icons=auto'
    alias ll='eza -l --icons=auto'
    alias la='eza -l -arbghi --git --icons=auto'
    alias lr='eza -lR -arbghi --git -I ".git|__pycache__" --icons=auto'
    alias lt='eza -lT -arbghi --git -I ".git|__pycache__|.terraform" --icons=auto'
    alias laa='eza -l -arbghi@ --git --icons=auto'
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
