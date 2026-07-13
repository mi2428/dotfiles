{ lib, pkgs, ... }:
let
  shellPackages = lib.optionals pkgs.stdenv.isLinux (with pkgs; [
    fish
    zsh
  ]);
in {
  # Keep shared command-line tools owned by Home Manager rather than language
  # package manifests that require an imperative update step.
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
    gopls
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
