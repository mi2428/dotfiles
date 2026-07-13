{ lib, platformFiles, ... }:
lib.mkIf (platformFiles.karabiner != null) {
  xdg.configFile."karabiner/karabiner.json" = {
    force = true;
    source = platformFiles.karabiner;
  };
}
