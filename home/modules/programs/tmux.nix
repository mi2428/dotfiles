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
    baseRoot = ../../../etc/tmux/tmux;
    overlays = {
      macos = ../../../etc/hosts/macos/tmux/tmux;
      "linux-server" = ../../../etc/hosts/linux-server/tmux/tmux;
      "docker-dev" = ../../../etc/hosts/docker/tmux/tmux;
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
    ".tmux.conf".source = ../../../etc/tmux/tmux.conf;
  };
}
