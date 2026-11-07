{
  config,
  lib,
  pkgs,
  userName,
  homeDirectory,
  ...
}:
let
  androidHost = import pkgs.path { system = "x86_64-linux"; };
in
{
  imports = [
    ../profiles/base.nix
    ../profiles/os/linux.nix
  ];

  # Reuse the macOS shell stack while retaining Omarchy's session bootstrap.
  # First activation: HOME_MANAGER_BACKUP_EXT=before-dotfiles ./bootstrap/bootstrap.sh
  # Register another machine in host-map.sh and adjust its display/device profile first.
  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
  # Activation integrations use OS-managed Herdr and AI tools from the caller's PATH.
  home.emptyActivationPath = false;
  # Secret archives may contain a macOS-only pinentry path.
  home.file.".gnupg/gpg-agent.conf" = {
    force = true;
    text = "pinentry-program /usr/bin/pinentry-gnome3\n";
  };
  # Install Brewfile counterparts with task pacman.sync before switching profiles.
  # Omarchy's existing mise policy is not changed by the package installation.
  # Ghostty, Herdr, and tmux honor SHELL. Changing passwd's login shell needs chsh.
  home.sessionVariables.SHELL = "${config.home.profileDirectory}/bin/fish";
  # Source through the project's local .envrc, not the global shell environment.
  # Store references keep QEMU's guest libraries alive across Nix garbage collection.
  xdg.dataFile."dropcheck-agent/env.sh".text = ''
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
    export ANDROID_HOME="$HOME/Android/Sdk"
    export ANDROID_USER_HOME="$HOME/.android"
    export GOTOOLCHAIN=go1.26.8
    export GOFLAGS=-p=1
    export PATH="$HOME/.local/share/dropcheck-agent/bin:$HOME/io/dropcheck-agent/controller/dist:$PATH"
    export QEMU_LD_PREFIX=${androidHost.glibc.out}
    export QEMU_SET_ENV=LD_LIBRARY_PATH=${androidHost.glibc.out}/lib:${androidHost.stdenv.cc.cc.lib}/lib:${androidHost.zlib}/lib
  '';
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
  home.activation.checkOmarchyIdentity = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    source ${../../bootstrap/host-map.sh}
    if [ "$(map_linux_machine_id_to_host "$(cat /etc/machine-id)")" != omarchy ]; then
      echo 'Refusing to apply Omarchy overrides to an unregistered machine.' >&2
      exit 1
    fi
    test -f /usr/share/omarchy/default/hypr/bootstrap.lua
  '';
  # Only our tool environment is continuously managed. Desktop preferences
  # remain writable files owned by Omarchy, not Home Manager.
  xdg.configFile."uwsm/env.d/90-dotfiles-nix".text = ''
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
  '';
}
