{ homeDirectory, userName, ... }:
let
  platform = {
    fish = {
      extraFiles = [ "conf.d/22_aliases.fish" ];
    };
    git = ../files/git/gitconfig.macos;
    tmux = {
      cpu = ../files/tmux/scripts/cpu.macos.sh;
      mem = ../files/tmux/scripts/mem.macos.sh;
    };
    zsh = {
      overrides = {
        "14_general_fzf.zsh" = ../files/zsh/14_general_fzf.macos.zsh;
        "22_aliases.zsh" = ../files/zsh/22_aliases.macos.zsh;
      };
    };
  };
in {
  dotfiles.platform = platform;

  imports = [
    ../profiles/base.nix
    ../profiles/os/macos.nix
  ];

  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
}
