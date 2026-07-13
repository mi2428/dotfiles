{ homeDirectory, userName, ... }:
let
  platform = {
    fish = {
      extraFiles = [];
    };
    git = ../files/git/gitconfig;
    tmux = {
      cpu = ../files/tmux/scripts/cpu.sh;
      mem = ../files/tmux/scripts/mem.sh;
    };
    zsh = {
      overrides = {
        "22_aliases.zsh" = ../files/zsh/22_aliases.zsh;
      };
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
