{
  lib,
  pkgs,
  userName,
  homeDirectory,
  ...
}:
{
  # Keep Omarchy's applications and shell defaults; add Nix and personal overrides.
  # First activation: HOME_MANAGER_BACKUP_EXT=before-dotfiles ./bootstrap/bootstrap.sh
  # Register another machine in host-map.sh and adjust its display/device profile first.
  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
  home.packages = [ pkgs.go-task ];
  home.sessionPath = [ "$HOME/.nix-profile/bin" ];
  programs.home-manager.enable = true;
  programs.bash = {
    enable = true;
    # Omarchy needs its environment even in non-interactive SSH shells.
    bashrcExtra = ''
      source /usr/share/omarchy/default/bash/env-bootstrap
      source "$HOME/.nix-profile/etc/profile.d/nix.sh"
    '';
    initExtra = ''
      source "$OMARCHY_PATH/default/bash/rc"
    '';
  };
  xdg.enable = true;

  home.activation.checkOmarchyIdentity = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    source ${../../bootstrap/host-map.sh}
    if [ "$(map_linux_machine_id_to_host "$(cat /etc/machine-id)")" != omarchy ]; then
      echo 'Refusing to apply Omarchy overrides to an unregistered machine.' >&2
      exit 1
    fi
    test -f /usr/share/omarchy/default/hypr/bootstrap.lua
  '';

  xdg.configFile = {
    "hypr/input.lua".source = ../files/config/hypr/omarchy/input.lua;
    "hypr/monitors.lua".source = ../files/config/hypr/omarchy/monitors.lua;
    "hypr/bindings.lua".source = ../files/config/hypr/omarchy/bindings.lua;
  };
}
