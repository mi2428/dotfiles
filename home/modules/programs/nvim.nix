{ ... }: {
  xdg.configFile."nvim" = {
    source = ../../../home/files/config/nvim;
    recursive = true;
  };
}
