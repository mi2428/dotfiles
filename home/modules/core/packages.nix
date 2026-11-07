{ lib, pkgs, platformName, ... }:
let
  clockpingRelease = {
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-xXxonfr4oiMBAdTimZlJ/V51KeDPFjggecISjTKDIQw=";
    };
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-L4qaZ4KE3KGT2WdyEABQfIDDFMRHbZaaw272BhP3riM=";
    };
  }.${pkgs.stdenv.hostPlatform.system};
  clockping = pkgs.stdenv.mkDerivation rec {
    pname = "clockping";
    version = "1.0.3";
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.glibc ];
    src = pkgs.fetchurl {
      url = "https://github.com/mi2428/clockping/releases/download/v${version}/clockping-v${version}-linux-${clockpingRelease.arch}";
      inherit (clockpingRelease) hash;
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 "$src" "$out/bin/clockping"
    '';
  };
  sharedPackages = with pkgs; [
    # Shell PTY e2e tests cannot find atuin inside the macOS Nix sandbox.
    (if stdenv.hostPlatform.isDarwin then
      atuin.overrideAttrs (old: {
        checkFlags = (old.checkFlags or [ ]) ++ [
          "--skip=filtered_commands_leave_no_captured_output"
          "--skip=setup_2_tests_shells_bash_preexec_toml"
        ];
      })
    else
      atuin)
    comrak
    eza
    fd
    fzf
    git
    gnupg
    # Build/task tooling; Summer Ghost's Python dependencies stay in upstream uv.lock.
    gnumake
    go-task
    nixfmt
    ripgrep
    shellcheck
    starship
    statix
    uv
    yazi
    zoxide
  ] ++ lib.optionals (platformName != "omarchy") [
    # Omarchy owns mise and Node through its system tool policy.
    pkgs.mise
    pkgs.nodejs
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
  dockerPackages = sharedPackages ++ containerDevPackages ++ [ clockping ];
  linuxPackages = sharedPackages ++ neovimPackages ++ [ clockping ];
in {
  # NOTE: Keep Nix package management limited to cross-platform shell-stack
  # basics. macOS-specific CLI and GUI packages live in the repo-root Brewfile
  # so routine Homebrew upgrades do not depend on a Nix store refresh first.
  home.packages =
    if pkgs.stdenv.hostPlatform.isDarwin then
      sharedPackages
    else if platformName == "docker" then
      dockerPackages
    else
      linuxPackages;
}
