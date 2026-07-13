{ pkgs, ... }: {
  home.packages = [ pkgs.neovim ];

  xdg.configFile."nvim" = {
    source = ../../../etc/nvim;
    recursive = true;
  };
}
