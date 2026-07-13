{ homeDirectory, userName, ... }: {
  imports = [
    ../profiles/base.nix
    ../profiles/os/macos.nix
  ];

  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
}
