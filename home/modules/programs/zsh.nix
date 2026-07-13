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
  pickSource = import ../../lib/pick-legacy-source.nix { inherit hostName; } {
    baseRoot = ../../../home/files/zsh/zsh;
    overlays = {
      macos = ../../../home/files/hosts/macos/zsh/zsh;
      "docker-dev" = ../../../home/files/hosts/docker-dev/zsh/zsh;
    };
  };
  zshFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair ".zsh/${relativePath}" {
        source = pickSource relativePath;
      })
    relativeFiles);
in {
  home.packages = [ pkgs.zsh ];

  home.file = zshFiles // {
    ".zshrc".source = ../../../home/files/zsh/zshrc;
    ".zlogin".source = ../../../home/files/zsh/zlogin;
  };
}
