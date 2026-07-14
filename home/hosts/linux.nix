{ homeDirectory, userName, ... }:
{
  imports = [
    ../profiles/base.nix
    ../profiles/os/linux.nix
    ../../system/linux/default.nix
  ];

  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
}
