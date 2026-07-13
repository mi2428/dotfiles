{ config, ... }:
let
  inherit (config.dotfiles) platform;
in {
  home.file = {
    ".gitconfig".source = platform.git;
    ".catppuccin-delta.gitconfig".source =
      ../../../home/files/git/catppuccin-delta.gitconfig;
  };
}
