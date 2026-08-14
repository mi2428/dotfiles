{ pkgs, ... }: {
  programs.direnv = {
    enable = true;
    enableFishIntegration = false;
    enableZshIntegration = !pkgs.stdenv.hostPlatform.isDarwin;
    nix-direnv.enable = true;
    silent = true;
  };
}
