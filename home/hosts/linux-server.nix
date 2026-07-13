{ homeDirectory, userName, ... }:
let
  platformFiles = {
    fish = {
      extraFiles = [];
    };
    git = ../files/git/gitconfig;
    tmux = {
      cpu = ../files/tmux/tmux/scripts/cpu.sh;
      mem = ../files/tmux/tmux/scripts/mem.sh;
    };
    vscode = {
      settingsTarget = ".config/Code/User/settings.json";
    };
    zsh = {
      overrides = {
        "22_aliases.zsh" = ../files/zsh/zsh/22_aliases.zsh;
      };
    };
  };
in {
  _module.args = { inherit platformFiles; };

  imports = [
    ../profiles/base.nix
    ../profiles/os/linux.nix
  ];

  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
}
