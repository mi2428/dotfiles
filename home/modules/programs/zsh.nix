{ hostName, lib, pkgs, ... }:
let
  relativeFiles = [
    "05_catppuccin_theme.zsh"
    "10_general.zsh"
    "12_general_path.zsh"
    "14_general_fzf.zsh"
    "20_aliases.zsh"
    "22_aliases.zsh"
    "30_appearance.zsh"
    "40_grc.zsh"
  ];
  sourceFor = relativePath:
    if relativePath == "12_general_path.zsh" && hostName == "macos" then
      ../../../home/files/zsh/zsh/12_general_path.macos.zsh
    else if relativePath == "14_general_fzf.zsh" && hostName == "macos" then
      ../../../home/files/zsh/zsh/14_general_fzf.macos.zsh
    else if relativePath == "22_aliases.zsh" && hostName == "macos" then
      ../../../home/files/zsh/zsh/22_aliases.macos.zsh
    else if relativePath == "22_aliases.zsh" && hostName == "docker-dev" then
      ../../../home/files/zsh/zsh/22_aliases.docker-dev.zsh
    else
      ../../../home/files/zsh/zsh/${relativePath};
  zshFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair ".zsh/${relativePath}" {
        source = sourceFor relativePath;
      })
    relativeFiles);
in {
  home.packages = [ pkgs.zsh ];

  home.file = zshFiles // {
    ".zshrc".source = ../../../home/files/zsh/zshrc;
    ".zlogin".source = ../../../home/files/zsh/zlogin;
  };
}
