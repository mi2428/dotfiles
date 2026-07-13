{ hostName, pkgs, ... }:
let
  pickSource = import ../../lib/pick-legacy-source.nix { inherit hostName; } {
    baseRoot = ../../../home/files/git;
    overlays = {
      macos = ../../../home/files/hosts/macos/git;
    };
  };
in {
  home.packages = [ pkgs.git ];

  home.file = {
    ".gitconfig".source = pickSource "gitconfig";
    ".catppuccin-delta.gitconfig".source =
      ../../../home/files/git/catppuccin-delta.gitconfig;
  };
}
