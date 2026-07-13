{ hostName, lib, pkgs, ... }:
let
  relativeFiles = [
    "scripts/battery-icon.sh"
    "scripts/battery.sh"
    "scripts/cpu.sh"
    "scripts/mem.sh"
    "scripts/storage.sh"
    "scripts/window-label.sh"
    "statusbar-catppuccin.conf"
    "statusbar.conf"
  ];
  pickSource = import ../../lib/pick-legacy-source.nix { inherit hostName; } {
    baseRoot = ../../../home/files/tmux/tmux;
    overlays = {
      macos = ../../../home/files/hosts/macos/tmux/tmux;
      "linux-server" = ../../../home/files/hosts/linux-server/tmux/tmux;
      "docker-dev" = ../../../home/files/hosts/docker-dev/tmux/tmux;
    };
  };
  tmuxFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair ".tmux/${relativePath}" {
        source = pickSource relativePath;
      })
    relativeFiles);
in {
  home.packages = [ pkgs.tmux ];

  home.file = tmuxFiles // {
    ".tmux.conf".source = ../../../home/files/tmux/tmux.conf;
  };
}
