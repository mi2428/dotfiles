{ lib, pkgs, platformFiles, ... }:
let
  catppuccinPlugin =
    "${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin";
  relativeFiles = [
    "scripts/battery-icon.sh"
    "scripts/battery.sh"
    "scripts/storage.sh"
    "scripts/window-label.sh"
    "statusbar-catppuccin.conf"
  ];
  sourceFor = relativePath:
    ../../../home/files/tmux/tmux/${relativePath};
  tmuxFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair ".tmux/${relativePath}" {
        source = sourceFor relativePath;
      })
    relativeFiles);
in {
  home.file = tmuxFiles // {
    ".tmux.conf".source = ../../../home/files/tmux/tmux.conf;
    ".tmux/scripts/cpu.sh".source = platformFiles.tmux.cpu;
    ".tmux/scripts/mem.sh".source = platformFiles.tmux.mem;
    ".tmux/statusbar.conf".source = ../../../home/files/tmux/tmux/statusbar.conf;
  };
  xdg.configFile."tmux/plugins/catppuccin/tmux" = {
    source = catppuccinPlugin;
  };
}
