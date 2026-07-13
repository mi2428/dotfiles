set -gx DENO_INSTALL $HOME/.deno
set -gx CARGO_HOME $HOME/.cargo
set -gx VOLTA_HOME $HOME/.volta
set -gx GOPATH $HOME/io/gocode

__dotfiles_set_path \
    $HOME/bin \
    $HOME/.nix-profile/bin \
    /run/current-system/sw/bin \
    /nix/var/nix/profiles/default/bin \
    $HOME/.local/bin \
    $DENO_INSTALL/bin \
    $CARGO_HOME/bin \
    $VOLTA_HOME/bin \
    /usr/bin \
    /usr/sbin \
    /bin \
    /sbin \
    /snap/bin \
    /usr/local/bin \
    /usr/local/sbin \
    .
