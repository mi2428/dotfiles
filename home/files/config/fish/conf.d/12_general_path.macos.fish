set -gx DENO_INSTALL $HOME/.deno
set -gx CARGO_HOME $HOME/.cargo
set -gx GOPATH $HOME/io/gocode
set -gx GOPRIVATE github.com/soracom

__dotfiles_import_posix_exports $HOME/.envs

switch (uname -m)
    case x86_64 i386
        set -gx HOMEBREW_HOME /usr/local
        set -gx VOLTA_HOME $HOME/.volta_x64
        set -gx FZF_BIN $HOMEBREW_HOME/opt/fzf/bin

        __dotfiles_set_path \
            $HOME/bin \
            $HOME/io/bin \
            $HOME/dotfiles/bin \
            $HOME/.local/bin \
            $GOPATH/bin \
            $DENO_INSTALL/bin \
            $CARGO_HOME/bin \
            $VOLTA_HOME/bin \
            /Applications/SnowSQL.app/Contents/MacOS \
            $HOME/.antigravity/antigravity/bin \
            $HOMEBREW_HOME/bin \
            $HOMEBREW_HOME/sbin \
            /usr/bin \
            /usr/sbin \
            /bin \
            /sbin \
            /Library/Apple/usr/bin \
            . \
            ./bin
    case arm64 '*'
        set -gx HOMEBREW_HOME /opt/homebrew
        set -gx VOLTA_HOME $HOME/.volta
        set -gx TEXLIVE_BIN /usr/local/texlive/2022/bin/universal-darwin
        set -gx FZF_BIN $HOMEBREW_HOME/opt/fzf/bin

        __dotfiles_set_path \
            $HOME/bin \
            $HOME/io/bin \
            $HOME/dotfiles/bin \
            $HOME/.local/bin \
            $GOPATH/bin \
            $DENO_INSTALL/bin \
            $CARGO_HOME/bin \
            $VOLTA_HOME/bin \
            $TEXLIVE_BIN \
            $FZF_BIN \
            /Applications/SnowSQL.app/Contents/MacOS \
            $HOME/.antigravity/antigravity/bin \
            $HOMEBREW_HOME/bin \
            $HOMEBREW_HOME/sbin \
            $HOMEBREW_HOME/opt/postgresql@13/bin \
            $HOMEBREW_HOME/opt/postgresql@14/bin \
            $HOMEBREW_HOME/opt/postgresql@15/bin \
            /usr/local/bin \
            /usr/local/sbin \
            /usr/bin \
            /usr/sbin \
            /bin \
            /sbin \
            /Library/Apple/usr/bin \
            . \
            ./bin
end

set -gx SDKMAN_DIR $HOME/.sdkman

if command -sq rbenv
    rbenv init - --no-rehash fish | source
end

if command -sq nodenv
    nodenv init - fish | source
end
