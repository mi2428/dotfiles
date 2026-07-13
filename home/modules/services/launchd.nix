{ lib, pkgs, ... }:
lib.mkIf pkgs.stdenv.isDarwin {
  launchd.agents = { };
}
