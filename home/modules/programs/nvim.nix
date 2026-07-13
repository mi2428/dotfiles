{ pkgs, ... }: {
  home.packages = [ pkgs.neovim ];

  xdg.configFile."nvim" = {
    source = ../../../home/files/config/nvim;
    recursive = true;
  };
}
