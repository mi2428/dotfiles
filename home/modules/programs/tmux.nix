{ hostName, lib, pkgs, ... }:
let
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
  home.packages = [ pkgs.tmux ];

  home.file = tmuxFiles // {
    ".tmux.conf".source = ../../../home/files/tmux/tmux.conf;
    ".tmux/scripts/cpu.sh".source =
      if hostName == "macos" then
        ../../../home/files/tmux/tmux/scripts/cpu.macos.sh
      else
        ../../../home/files/tmux/tmux/scripts/cpu.sh;
    ".tmux/scripts/mem.sh".source =
      if hostName == "macos" then
        ../../../home/files/tmux/tmux/scripts/mem.macos.sh
      else
        ../../../home/files/tmux/tmux/scripts/mem.sh;
    ".tmux/statusbar.conf".source = ../../../home/files/tmux/tmux/statusbar.conf;
  };
}
