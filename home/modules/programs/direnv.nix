{ pkgs, ... }: {
  programs.direnv = {
    enable = true;
    enableZshIntegration = !pkgs.stdenv.isDarwin;
    nix-direnv.enable = true;
    silent = true;
  };
}
