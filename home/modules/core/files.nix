{ ... }:
let
  mkLink = source: {
    force = true;
    inherit source;
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

  home.file = {
    ".curlrc" = mkLink ../../files/curl/curlrc;
    ".lesskey" = mkLink ../../files/less/lesskey;
    ".screenrc" = mkLink ../../files/screen/screenrc;
    ".wgetrc" = mkLink ../../files/wget/wgetrc;
  };
}
