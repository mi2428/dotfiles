{ config, lib, pkgs, ... }:
let
  inherit (config.dotfiles) platform;
  catppuccinTmux = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "tmux";
    rev = "v2.3.0";
    hash = "sha256-3CJRQCgS8NAN7vOLBjNGiHbGXTIrIyY/FLmfZrXcEYc=";
  };
  tmuxFiles = [
    "scripts/battery-icon.sh"
    "scripts/battery.sh"
    "scripts/edit-scrollback.sh"
    "scripts/lazygit-popup.sh"
    "scripts/storage.sh"
    "scripts/window-label.sh"
    "scripts/yazi-popup.sh"
    "scripts/yazi-tmux-open.sh"
    "statusbar-catppuccin.conf"
  ];
  sourceFor = relativePath:
    ../../../home/files/tmux/${relativePath};
  helperFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair ".tmux/${relativePath}" {
        source = sourceFor relativePath;
      })
    tmuxFiles);
in {
  home.file = helperFiles // {
    ".tmux.conf" = {
      force = true;
      source = ../../../home/files/tmux/tmux.conf;
    };
    ".tmux/scripts/cpu.sh".source = platform.tmux.cpu;
    ".tmux/scripts/mem.sh".source = platform.tmux.mem;
    ".tmux/statusbar.conf".source = ../../../home/files/tmux/statusbar.conf;
  };

  xdg.configFile = {
    "tmux/plugins/catppuccin/tmux" = {
      recursive = true;
      source = catppuccinTmux;
    };
  };
}
