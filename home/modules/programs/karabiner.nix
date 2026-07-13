{ ... }: {
  xdg.configFile."karabiner/karabiner.json" = {
    force = true;
    source = ../../../home/files/config/karabiner/karabiner.json;
  };
}
