{ homeDirectory, userName, lib, ... }: {
  imports = [
    ../profiles/base.nix
    ../profiles/os/macos.nix
  ];

  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";

  xdg.configFile."ghostty/config".text = lib.mkAfter "\nfont-size = 14\n";
}
