{ lib, pkgs, platformName, ... }:
let
  linuxEssentialPackages = with pkgs; [
    eza
    fd
    fzf
    git
    ripgrep
    starship
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
  darwinBasePackages = with pkgs; [
    bash
    bat
    coreutils
    delta
    gh
    git-lfs
    gitflow
    gnugrep
    gnupg
    jq
    neovim
    python313Packages.pynvim
    tig
    tmux
    tree
    watch
    wget
    yq-go
  ];
  nonContainerPackages = with pkgs; [
    black
    cargo-dist
    cmake
    colordiff
    cowsay
    csvkit
    cue
    deno
    difftastic
    eksctl
    expect
    figlet
    fq
    frogmouth
    glances
    glow
    gotools
    grc
    gum
    herdr
    hexyl
    htop
    httpie
    ipcalc
    iperf3
    ipinfo
    isort
    jnv
    k9s
    kubectl
    lazygit
    libssh
    most
    mtools
    mtr
    net-snmp
    nfdump
    nkf
    nmap
    ollama
    oui
    pipenv
    pipx
    poetry
    poppler
    procs
    protobuf
    pv
    rbenv
    rich-cli
    rustup
    silver-searcher-ng
    sops
    speedtest-cli
    tailspin
    terraform
    tokei
    (lib.hiPrio tmuxinator)
    viddy
    yt-dlp
    zig
  ];
  darwinPackages = darwinBasePackages ++ containerDevPackages ++ nonContainerPackages ++ (with pkgs; [
    _1password-cli
    android-tools
    claude-code
    codex
    iproute2mac
    mas
    pinentry_mac
    postgresql_14
    ssm-session-manager-plugin
    swift-format
    swiftformat
    swiftlint
    temurin-bin-17
  ]);
  dockerPackages = linuxEssentialPackages ++ containerDevPackages;
  linuxPackages = linuxEssentialPackages;
in {
  # Keep Linux minimal: only lightweight interactive tools that are commonly
  # missing on fresh systems but materially improve the managed shell setup.
  home.packages =
    if pkgs.stdenv.isDarwin then
      darwinPackages
    else if platformName == "docker" then
      dockerPackages
    else
      linuxPackages;
}
