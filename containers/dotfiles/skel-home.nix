{ system ? builtins.currentSystem }:
let
  repoRoot = ../..;
  flake = builtins.getFlake (toString repoRoot);
  mkLinux = import ../../system/linux/lib/mk-linux.nix {
    inherit (flake) inputs;
  };
in
(mkLinux {
  inherit system;
  systemModule = ../../system/linux/hosts/ubuntu.nix;
  homeModule = ../../home/hosts/docker.nix;
  platformName = "docker";
  hostName = "docker-dev";
  userName = "skel";
  homeDirectory = "/tmp/skel";
}).activationPackage
