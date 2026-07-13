{ config, lib, pkgs, ... }:
let
  inherit (config.lib.file) mkOutOfStoreSymlink;
  mkLink = source: {
    force = true;
    inherit source;
  };
  binRoot = ../../../bin;
  binFiles = lib.mapAttrs'
    (name: _: lib.nameValuePair ".local/bin/${name}" (mkLink (binRoot + "/${name}")))
    (lib.filterAttrs (_: type: type == "regular") (builtins.readDir binRoot));
  macCompatibilityFiles = lib.optionalAttrs pkgs.stdenv.isDarwin {
    "Library/Application Support/com.mitchellh.ghostty/config.ghostty" =
      mkLink (mkOutOfStoreSymlink "${config.xdg.configHome}/ghostty/config.ghostty");
    "Library/Application Support/com.mitchellh.ghostty/themes" =
      mkLink (mkOutOfStoreSymlink "${config.xdg.configHome}/ghostty/themes");
    "Library/Application Support/lazygit/config.yml" =
      mkLink (mkOutOfStoreSymlink "${config.xdg.configHome}/lazygit/config.yml");
    "Library/Application Support/lazygit/functions.sh" =
      mkLink (mkOutOfStoreSymlink "${config.xdg.configHome}/lazygit/functions.sh");
    "Library/Application Support/lazygit/themes-mergable" =
      mkLink (mkOutOfStoreSymlink "${config.xdg.configHome}/lazygit/themes-mergable");
    "Library/Application Support/k9s/config.yaml" =
      mkLink (mkOutOfStoreSymlink "${config.xdg.configHome}/k9s/config.yaml");
    "Library/Application Support/k9s/skins" =
      mkLink (mkOutOfStoreSymlink "${config.xdg.configHome}/k9s/skins");
  };
in {
  xdg.configFile = {
    "bat" = mkLink ../../files/config/bat;
    "eza" = mkLink ../../files/config/eza;
    "fzf" = mkLink ../../files/config/fzf;
    "ghostty" = mkLink ../../files/config/ghostty;
    "glow" = mkLink ../../files/config/glow;
    "herdr" = mkLink ../../files/config/herdr;
    "hunk" = mkLink ../../files/config/hunk;
    "k9s" = mkLink ../../files/config/k9s;
    "lazygit" = mkLink ../../files/config/lazygit;
    "starship" = mkLink ../../files/config/starship;
  };

  home.file = binFiles // macCompatibilityFiles // {
    ".curlrc" = mkLink ../../files/curl/curlrc;
    ".lesskey" = mkLink ../../files/less/lesskey;
    ".screenrc" = mkLink ../../files/screen/screenrc;
    ".wgetrc" = mkLink ../../files/wget/wgetrc;
  };
}
