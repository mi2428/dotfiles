{ pkgs, self, userName, ... }: {
  nixpkgs.config.allowUnfree = true;

  ids.gids.nixbld = 350;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.trusted-users = [
    "@admin"
    userName
  ];
  nix.optimise.automatic = true;

  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
  };

  programs.fish.enable = true;
  programs.zsh.enable = true;

  users.users.${userName}.shell = pkgs.fish;

  # NOTE: Keep nix-darwin's Homebrew module disabled. Managing Homebrew state
  # from the repo-root Brewfile keeps routine brew upgrades independent from a
  # Nix store refresh. Only cross-platform shell-stack basics stay in Nix.
  #
  # Re-enable this module only if Homebrew state needs to be coupled back into
  # nix-darwin activation:
  #
  # homebrew = {
  #   enable = true;
  #   user = userName;
  #   global = {
  #     autoUpdate = true;
  #     brewfile = true;
  #   };
  #   onActivation = {
  #     autoUpdate = false;
  #     cleanup = "none";
  #     upgrade = false;
  #   };
  # };

  system.activationScripts.cleanupLegacyCodexApp.text = ''
    if [ -L /opt/homebrew/Caskroom/codex-app ]; then
      rm -f /opt/homebrew/Caskroom/codex-app
    fi
  '';

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 6;
}
