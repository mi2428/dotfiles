{ config, ... }:
let
  inherit (config.dotfiles) platform;
in {
  programs.git = {
    enable = true;
    includes = [
      { path = platform.git; }
    ];
  };

  home.file.".catppuccin-delta.gitconfig".source =
    ../../../home/files/git/catppuccin-delta.gitconfig;
}
