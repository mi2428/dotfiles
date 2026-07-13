{ hostName, lib, pkgs, ... }:
lib.mkIf (pkgs.stdenv.isDarwin && hostName == "macos") {
  xdg.configFile."karabiner/karabiner.json" = {
    force = true;
    source = ../../../home/files/hosts/macos/karabiner/karabiner.json;
  };
}
