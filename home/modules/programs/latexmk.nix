{ lib, pkgs, ... }:
lib.mkIf pkgs.stdenv.isDarwin {
  home.file.".latexmkrc" = {
    force = true;
    source = ../../files/latexmk/latexmkrc;
  };
}
