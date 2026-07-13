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

  homebrew = {
    enable = true;
    user = userName;
    taps = [
      "aws/tap"
      "fujiwara/tap"
      "hashicorp/tap"
      "homebrew/cask-fonts"
      "mi2428/clockping"
      "mi2428/fing"
      "mi2428/iperf3-rs"
      "textualize/rich"
      "thatmattlove/oui"
      "wader/tap"
      "ynqa/tap"
    ];
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
      "chrony"
      "hunk"
      "ifstat"
      "iperf3-rs"
      "ruby-build"
      "trash"
      "zsh-git-prompt"
    ];
    casks = [
      "android-studio"
      "blackhole-16ch"
      "codex-app"
      "font-hack-nerd-font"
      "ghostty"
      "karabiner-elements"
      "kiro"
      "multipass"
      "visual-studio-code"
    ];
  };

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 6;
}
