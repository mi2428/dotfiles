{ pkgs, platformName, ... }:
let
  sharedPackages = with pkgs; [
    atuin
    eza
    fd
    fzf
    git
    ripgrep
    starship
    yazi
    zoxide
  ];
  containerDevPackages = with pkgs; [
    actionlint
    bash-language-server
    go-tools
    golangci-lint
    gopls
    hadolint
    lua-language-server
    nixd
    pre-commit
    pyright
    python313Packages.python-lsp-server
    ruff
    shfmt
    stylua
    taplo
    terraform-ls
    tflint
    uv
    yaml-language-server
    yarn
  ];
  dockerPackages = sharedPackages ++ containerDevPackages;
  linuxPackages = sharedPackages;
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
