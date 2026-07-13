{ config, lib, pkgs, ... }:
let
  inherit (config.dotfiles) platform;
  tmuxFiles = [
    "scripts/battery-icon.sh"
    "scripts/battery.sh"
    "scripts/storage.sh"
    "scripts/window-label.sh"
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
    ".tmux/scripts/cpu.sh".source = platform.tmux.cpu;
    ".tmux/scripts/mem.sh".source = platform.tmux.mem;
    ".tmux/statusbar.conf".source = ../../../home/files/tmux/statusbar.conf;
  };

  programs.tmux = {
    enable = true;
    prefix = "C-t";
    terminal = "xterm-256color";
    baseIndex = 1;
    historyLimit = 10000000;
    escapeTime = 0;
    focusEvents = true;
    mouse = true;
    plugins = [ pkgs.tmuxPlugins.catppuccin ];
    extraConfig = builtins.readFile ../../../home/files/tmux/tmux.conf;
  };
}
