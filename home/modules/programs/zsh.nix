{ config, lib, ... }:
let
  inherit (config.dotfiles) platform;
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
    if builtins.hasAttr relativePath platform.zsh.overrides then
      platform.zsh.overrides.${relativePath}
    else
      ../../../home/files/zsh/${relativePath};
  initFragments = map
    (relativePath: ''
      # ${relativePath}
      ${builtins.readFile (sourceFor relativePath)}
    '')
    relativeFiles;
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    completionInit = "";
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    # The sourced assets still own most shell behavior; HM owns the assembly
    # order and surrounding integration.
    initContent = lib.mkOrder 550 (lib.concatStringsSep "\n" initFragments);
  };
}
