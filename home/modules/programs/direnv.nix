{ pkgs, ... }: {
  programs.direnv = {
    enable = true;
    enableFishIntegration = false;
    enableZshIntegration = !pkgs.stdenv.isDarwin;
    nix-direnv.enable = true;
    silent = true;
  };
}
