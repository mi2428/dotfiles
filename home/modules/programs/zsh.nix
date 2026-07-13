{ lib, platformFiles, ... }:
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
    if builtins.hasAttr relativePath platformFiles.zsh.overrides then
      platformFiles.zsh.overrides.${relativePath}
    else
      ../../../home/files/zsh/${relativePath};
  zshFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair ".zsh/${relativePath}" {
        source = sourceFor relativePath;
      })
    relativeFiles);
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = ''
      for conf in "$HOME"/.zsh/*.zsh(N); do
        source "$conf"
      done
    '';
  };

  home.file = zshFiles;
}
