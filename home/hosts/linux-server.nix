{ ... }: {
  imports = [
    ../profiles/base.nix
    ../profiles/os/linux.nix
    ../profiles/role/server.nix
  ];

  home.username = "teo";
  home.homeDirectory = "/home/teo";
  home.stateVersion = "25.05";
}
