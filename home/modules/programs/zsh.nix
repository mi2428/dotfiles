{ config, lib, pkgs, ... }:
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
  zshFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair ".zsh/${relativePath}" {
        force = true;
        source = sourceFor relativePath;
      })
    relativeFiles);
in {
  home.file = zshFiles // {
    ".local/share/zsh/site-functions" = {
      force = true;
      source = "${pkgs.zsh-completions}/share/zsh/site-functions";
    };
    ".local/share/zsh/zsh-autosuggestions" = {
      force = true;
      source = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
    };
    ".local/share/zsh/zsh-syntax-highlighting" = {
      force = true;
      source = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting";
    };
  } // {
    ".zlogin" = {
      force = true;
      source = ../../../home/files/zsh/zlogin;
    };
    ".zshrc" = {
      force = true;
      source = ../../../home/files/zsh/zshrc;
    };
  };
}
