{ homeDirectory, userName, ... }:
let
  platformFiles = {
    fish = {
      path = ../files/config/fish/conf.d/12_general_path.macos.fish;
      extraFiles = [ "conf.d/22_aliases.fish" ];
    };
    git = ../files/git/gitconfig.macos;
    karabiner = ../files/config/karabiner/karabiner.json;
    tmux = {
      cpu = ../files/tmux/tmux/scripts/cpu.macos.sh;
      mem = ../files/tmux/tmux/scripts/mem.macos.sh;
    };
    vscode = {
      settingsTarget = "Library/Application Support/Code/User/settings.json";
    };
    zsh = {
      overrides = {
        "12_general_path.zsh" = ../files/zsh/zsh/12_general_path.macos.zsh;
        "14_general_fzf.zsh" = ../files/zsh/zsh/14_general_fzf.macos.zsh;
        "22_aliases.zsh" = ../files/zsh/zsh/22_aliases.macos.zsh;
      };
    };
  };
in {
  _module.args = { inherit platformFiles; };

  imports = [
    ../profiles/base.nix
    ../profiles/os/macos.nix
  ];

  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
}
