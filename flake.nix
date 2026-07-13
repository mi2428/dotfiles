{
  description = "Teo's Nix-first dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, ... }:
  let
    mkHome = import ./home/lib/mk-home.nix { inherit inputs; };
    mkDarwin = import ./darwin/lib/mk-darwin.nix {
      inherit inputs self;
    };
  in
  {
    darwinConfigurations = {
      macos = mkDarwin {
        system = "aarch64-darwin";
        darwinModule = ./darwin/hosts/macos.nix;
        homeModule = ./home/hosts/macos.nix;
        hostName = "macos";
        userName = "teo";
        homeDirectory = "/Users/teo";
      };
    };

    homeConfigurations = {
      "linux-server" = mkHome {
        system = "aarch64-linux";
        hostModule = ./home/hosts/linux-server.nix;
        hostName = "linux-server";
        userName = "teo";
        homeDirectory = "/home/teo";
      };

      "docker-dev" = mkHome {
        system = "x86_64-linux";
        hostModule = ./home/hosts/docker-dev.nix;
        hostName = "docker-dev";
        userName = "teo";
        homeDirectory = "/home/teo";
      };
    };
  };
}
