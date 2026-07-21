{ ... }: {
  programs.broot = {
    enable = true;
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    enableZshIntegration = false;
    settings.imports = [
      "${../../files/config/broot/catppuccin-mocha-mauve.hjson}"
    ];
  };
}
