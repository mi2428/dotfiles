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
    envOr = name: fallback:
      let
        value = builtins.getEnv name;
      in
      if value != "" then value else fallback;
  in {
    homeConfigurations = {
      macos = mkHome {
        system = "aarch64-darwin";
        hostModule = ./home/hosts/macos.nix;
        hostName = "macos";
      };

      "linux-server" = mkHome {
        system = envOr "DOTFILES_NIX_SYSTEM" "aarch64-linux";
        hostModule = ./home/hosts/linux-server.nix;
        hostName = "linux-server";
      };

      "docker-dev" = mkHome {
        system = envOr "DOTFILES_NIX_SYSTEM" "x86_64-linux";
        hostModule = ./home/hosts/docker-dev.nix;
        hostName = "docker-dev";
      };
    };
  };
}
