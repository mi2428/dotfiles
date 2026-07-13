{ homeDirectory, userName, ... }:
let
  platform = {
    zsh.overrides = {
      "22_aliases.zsh" = ../files/zsh/22_aliases.docker.zsh;
    };
  };
in {
  dotfiles.platform = platform;

  imports = [
    ../profiles/base.nix
    ../profiles/os/linux.nix
  ];

  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
}
