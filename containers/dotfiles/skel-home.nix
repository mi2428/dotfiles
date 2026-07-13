{ system ? builtins.currentSystem }:
let
  repoRoot = ../..;
  flake = builtins.getFlake (toString repoRoot);
  mkHome = import ../../home/lib/mk-home.nix {
    inherit (flake) inputs;
  };
in
(mkHome {
  inherit system;
  hostModule = ../../home/hosts/docker-dev.nix;
  hostName = "docker-dev";
  userName = "skel";
  homeDirectory = "/tmp/skel";
}).activationPackage
