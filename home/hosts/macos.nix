{ ... }: {
  imports = [
    ../profiles/base.nix
    ../profiles/os/macos.nix
    ../profiles/role/desktop.nix
  ];

  home.username = "teo";
  home.homeDirectory = "/Users/teo";
  home.stateVersion = "25.05";
}
