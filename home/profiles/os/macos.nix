{ ... }: {
  imports = [
    ../../modules/programs/karabiner.nix
    ../../modules/programs/vscode.nix
  ];

  home.sessionPath = [
    "/run/current-system/sw/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/usr/local/bin"
    "/usr/local/sbin"
  ];
}
