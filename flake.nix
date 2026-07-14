{
  description = "mi2428/dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, ... }:
  let
    envOr = name: fallback:
      let
        value = builtins.getEnv name;
      in
      if value != "" then value else fallback;
    mkDarwin = import ./system/darwin/lib/mk-darwin.nix {
      inherit inputs self;
    };
    mkLinux = import ./system/linux/lib/mk-linux.nix { inherit inputs; };
    macosConfig = mkDarwin {
      system = "aarch64-darwin";
      darwinModule = ./system/darwin/hosts/macos.nix;
      homeModule = ./home/hosts/macos.nix;
      platformName = "macos";
      hostName = "macos";
      userName = "teo";
      homeDirectory = "/Users/teo";
    };
  in
  {
    darwinConfigurations = {
      "macos" = macosConfig;
    };

    homeConfigurations = {
      "linux" = mkLinux {
        system = "aarch64-linux";
        systemModule = ./system/linux/hosts/ubuntu.nix;
        homeModule = ./home/hosts/linux.nix;
        platformName = "linux";
        hostName = "linux";
        userName = envOr "DOTFILES_RUNTIME_USER" "teo";
        homeDirectory = envOr "DOTFILES_RUNTIME_HOME" "/home/teo";
      };

      "docker" = mkLinux {
        system = "x86_64-linux";
        systemModule = ./system/linux/hosts/ubuntu.nix;
        homeModule = ./home/hosts/docker.nix;
        platformName = "docker";
        hostName = "docker";
        userName = envOr "DOTFILES_RUNTIME_USER" "teo";
        homeDirectory = envOr "DOTFILES_RUNTIME_HOME" "/home/teo";
      };
    };
  };
}
