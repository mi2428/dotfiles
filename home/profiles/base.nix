{ ... }: {
  imports = [
    ../modules/core
    ../modules/programs
    ../modules/services
  ];

  programs.home-manager.enable = true;
  xdg.enable = true;
}
