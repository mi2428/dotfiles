{
  description = "Teo's Home Manager-first dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nixpkgs, ... }:
  let
    mkHome = import ./home/lib/mk-home.nix { inherit inputs; };
  in {
    homeConfigurations = {
      macos = mkHome {
        system = "aarch64-darwin";
        hostModule = ./home/hosts/macos.nix;
      };

      "linux-server" = mkHome {
        system = "x86_64-linux";
        hostModule = ./home/hosts/linux-server.nix;
      };

      "docker-dev" = mkHome {
        system = "x86_64-linux";
        hostModule = ./home/hosts/docker-dev.nix;
      };
    };
  };
}
