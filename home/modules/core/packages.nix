{ pkgs, ... }: {
  # Keep shared command-line tools owned by Home Manager rather than language
  # package manifests that require an imperative update step.
  home.packages = with pkgs; [
    eza
    fd
    git
    neovim
    procs
    ripgrep
    tmux
  ];
}
