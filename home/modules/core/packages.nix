{ lib, pkgs, platformName, ... }:
let
  podmanLatest = pkgs.podman.overrideAttrs (_: rec {
    version = "6.0.1";
    src = pkgs.fetchFromGitHub {
      owner = "containers";
      repo = "podman";
      tag = "v${version}";
      hash = "sha256-EUoxguIMBhpUBOtfNyA7rxPE2y1tB+Y2lu0UVHpXe8o=";
    };
  });
  linuxEssentialPackages = with pkgs; [
    atuin
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
    atuin
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
    aws-cdk-cli
    aws-sam-cli
    awscli2
    buildah
    claude-code
    codex
    docker
    docker-compose
    go
    gradle
    iproute2mac
    mas
    nodejs
    pinentry_mac
    playwright-driver
    podmanLatest
    podman-compose
    postgresql_14
    skopeo
    ssm-session-manager-plugin
    swift-format
    swiftformat
    swiftlint
    temurin-bin-17
    vhs
    vscode-langservers-extracted
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
