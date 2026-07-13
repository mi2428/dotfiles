{ ... }: {
  imports = [
    ../modules/dotfiles
    ../modules/core
    ../modules/programs
  ];

  programs.home-manager.enable = true;
  xdg.enable = true;
}
