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
      {
        name = "aws/tap";
        trusted = true;
      }
      {
        name = "fujiwara/tap";
        trusted = true;
      }
      {
        name = "hashicorp/tap";
        trusted = true;
      }
      {
        name = "mi2428/clockping";
        trusted = true;
      }
      {
        name = "mi2428/fing";
        trusted = true;
      }
      {
        name = "mi2428/iperf3-rs";
        trusted = true;
      }
      {
        name = "textualize/rich";
        trusted = true;
      }
      {
        name = "thatmattlove/oui";
        trusted = true;
      }
      {
        name = "wader/tap";
        trusted = true;
      }
      {
        name = "ynqa/tap";
        trusted = true;
      }
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
      "go-task"
      "hunk"
      "ifstat"
      "mi2428/iperf3-rs/iperf3-rs"
      "ruby-build"
      "trash"
      "zsh-git-prompt"
    ];
    casks = [
      "android-studio"
      "blackhole-16ch"
      "font-hack-nerd-font"
      "ghostty"
      "chatgpt"
      "karabiner-elements"
      "kiro"
      "multipass"
      "visual-studio-code"
    ];
  };

  system.activationScripts.cleanupLegacyCodexApp.text = ''
    if [ -L /opt/homebrew/Caskroom/codex-app ]; then
      rm -f /opt/homebrew/Caskroom/codex-app
    fi
  '';

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 6;
}
