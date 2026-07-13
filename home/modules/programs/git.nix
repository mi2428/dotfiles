{ hostName, pkgs, ... }:
let
  pickSource = import ../../lib/pick-legacy-source.nix { inherit hostName; } {
    baseRoot = ../../../etc/git;
    overlays = {
      macos = ../../../etc/hosts/macos/git;
    };
  };
in {
  home.packages = [ pkgs.git ];

  home.file = {
    ".gitconfig".source = pickSource "gitconfig";
    ".catppuccin-delta.gitconfig".source =
      ../../../etc/git/catppuccin-delta.gitconfig;
  };
}
