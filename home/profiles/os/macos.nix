{ ... }: {
  imports = [
    ../../modules/programs/karabiner.nix
  ];

  home.sessionPath = [
    "/run/current-system/sw/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/usr/local/bin"
    "/usr/local/sbin"
  ];
}
