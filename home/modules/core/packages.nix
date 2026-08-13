{ pkgs, platformName, ... }:
let
  sharedPackages = with pkgs; [
    atuin
    comrak
    eza
    fd
    fzf
    git
    gnupg
    mise
    nixfmt
    nodejs
    ripgrep
    shellcheck
    starship
    statix
    uv
    yazi
    zoxide
  ];
  neovimPackages = with pkgs; [
    actionlint
    bash-language-server
    black
    dockerfile-language-server
    go-tools
    golangci-lint
    gopls
    hadolint
    imagemagick
    lua-language-server
    pyright
    ruff
    rust-analyzer
    rustfmt
    shfmt
    stylua
    terraform-ls
    tflint
    vscode-langservers-extracted
    yaml-language-server
  ];
  containerDevPackages = neovimPackages ++ (with pkgs; [
    gh
    nixd
    pre-commit
    python313Packages.python-lsp-server
    taplo
    yarn
    zsh
  ]);
  dockerPackages = sharedPackages ++ containerDevPackages;
  linuxPackages = sharedPackages ++ neovimPackages;
in {
  # NOTE: Keep Nix package management limited to cross-platform shell-stack
  # basics. macOS-specific CLI and GUI packages live in the repo-root Brewfile
  # so routine Homebrew upgrades do not depend on a Nix store refresh first.
  home.packages =
    if pkgs.stdenv.isDarwin then
      sharedPackages
    else if platformName == "docker" then
      dockerPackages
    else
      linuxPackages;
}
