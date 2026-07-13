{ pkgs, ... }: {
  # Keep shared command-line tools owned by Home Manager rather than language
  # package manifests that require an imperative update step.
  home.packages = with pkgs; [
    bat
    delta
    direnv
    eza
    fd
    fish
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
    zsh
  ];
}
