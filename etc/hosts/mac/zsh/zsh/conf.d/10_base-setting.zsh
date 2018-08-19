export HISTSIZE=1000000
export SAVEHIST=1000000
export HISTFILE=$HOME/.zhistory
setopt BANG_HIST                    ## use csh extended history
# setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt ALWAYS_TO_END
setopt NO_BEEP
setopt AUTO_CD
setopt AUTOPUSHD
setopt PUSHD_IGNORE_DUPS
setopt CORRECT
# setopt CORRECT_ALL
setopt MAGIC_EQUAL_SUBST
setopt PROMPT_SUBST
setopt NOTIFY
setopt AUTO_LIST
setopt AUTO_MENU
setopt LIST_PACKED
setopt LIST_TYPES
setopt NO_LIST_BEEP
setopt IGNORE_EOF                   ## ignore <C-d>
setopt NO_AUTOREMOVESLASH

##
## Path
##
export XDG_CONFIG_HOME=$HOME/.config
export ZPLUG_HOME=$HOME/.zsh/zplug
export GEMPATH=$HOME/.gem/ruby/2.3.0/bin
export DOT_BIN=$HOME/bin
export ECLIPSE=$HOME/eclipse/java-neon/eclipse
export GOPATH=$HOME/.go
export HEROKU=/usr/local/heroku/bin
export RUBYGEM=/home/taichi/.gem/ruby/2.4.0/bin
export PATH=$DOT_BIN:/usr/local/bin:/usr/local/sbin:$PATH:$GOPATH/bin:$RIAKPATH:$GEMPATH:$ECLIPSE:$HEROKU:$RUBYGEM
export GPG_TTY=$(tty)

##
## time
##
REPORTTIME=30
TIMEFMT="job: %J
time: %E (user: %U kernel: %S)
cpu: %P"

##
## Completion
##

# `-C` is for faster boot.
# -C: skip security check (see http://zsh.sourceforge.net/Doc/Release/Completion-System.html#index-compinit )
autoload -Uz compinit
compinit -C

zstyle ':completion:*:default' menu select=2
zstyle ':completion:*' verbose yes
zstyle ':completion:*' completer _expand _complete _match _prefix _approximate _list _history
zstyle ':completion:*:messages' format '%F{YELLOW}%d'$DEFAULT
zstyle ':completion:*:warnings' format '%F{RED}No matches for:''%F{YELLOW} %d'$DEFAULT
zstyle ':completion:*:descriptions' format '%F{YELLOW}completing %B%d%b'$DEFAULT
zstyle ':completion:*:options' description 'yes'
zstyle ':completion:*:descriptions' format '%F{yellow}Completing %B%d%b%f'$DEFAULT
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-separator '-->'
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*:sudo:*' command-path $path
