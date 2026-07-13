__dotfiles_import_posix_exports $HOME/.envs

switch (uname -m)
    case x86_64 i386
        set -gx HOMEBREW_HOME /usr/local
        set -gx VOLTA_HOME $HOME/.volta_x64
        set -gx FZF_BIN $HOMEBREW_HOME/opt/fzf/bin

    case arm64 '*'
        set -gx HOMEBREW_HOME /opt/homebrew
        set -gx VOLTA_HOME $HOME/.volta
        set -gx TEXLIVE_BIN /usr/local/texlive/2022/bin/universal-darwin
        set -gx FZF_BIN $HOMEBREW_HOME/opt/fzf/bin

end

set -gx SDKMAN_DIR $HOME/.sdkman

if command -sq rbenv
    rbenv init - --no-rehash fish | source
end

if command -sq nodenv
    nodenv init - fish | source
end
