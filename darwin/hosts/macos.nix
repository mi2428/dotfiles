{ pkgs, self, userName, ... }: {
  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin";

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

  homebrew = {
    enable = true;
    user = userName;
    global = {
      autoUpdate = true;
      brewfile = true;
    };
    onActivation = {
      autoUpdate = false;
      cleanup = "none";
      upgrade = false;
    };
    brews = [
      "pinentry-mac"
    ];
    casks = [
      "ghostty"
      "karabiner-elements"
      "visual-studio-code"
    ];
  };

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 6;
}
