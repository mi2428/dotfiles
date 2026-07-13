{ lib, pkgs, ... }:
let
  shellPackages = lib.optionals pkgs.stdenv.isLinux (with pkgs; [
    fish
    zsh
  ]);
in {
  # Keep shared command-line tools owned by Home Manager instead of imperative
  # per-language global installs.
  home.packages = (with pkgs; [
    bat
    delta
    eza
    fd
    fzf
    git
    glow
    go
    go-tools
    gotools
    gopls
    frogmouth
    grc
    jq
    k9s
    kubectl
    lazygit
    mtr
    neovim
    nodejs
    python3Packages.pynvim
    procs
    ripgrep
    rust-analyzer
    starship
    terraform
    tmux
    tree
    zoxide
  ]) ++ shellPackages;
}
