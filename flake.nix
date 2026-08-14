{
  description = "mi2428/dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    gh-inbox.url = "github:mi2428/gh-inbox";
    gh-inbox.flake = false;
    luamigemo.url = "github:delphinus/luamigemo/v1.4.1";
    luamigemo.flake = false;
    migemo-dict.url = "github:oguna/migemo-compact-dict-latest";
    migemo-dict.flake = false;
    lingua-motion.url = "git+ssh://git@github.com/mi2428/lingua-motion.nvim.git?ref=refs/tags/v1.0.0";
    lingua-motion.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, ... }:
  let
    envOr = name: fallback:
      let
        value = builtins.getEnv name;
      in
      if value != "" then value else fallback;
    runtimeLinuxSystem =
      let
        value = envOr "DOTFILES_RUNTIME_SYSTEM" "";
      in
      if builtins.elem value [
        "aarch64-linux"
        "x86_64-linux"
      ] then
        value
      else
        "aarch64-linux";
    mkDarwin = import ./system/darwin/lib/mk-darwin.nix {
      inherit inputs self;
    };
    mkLinux = import ./system/linux/lib/mk-linux.nix { inherit inputs; };
    mkHome = import ./home/lib/mk-home.nix { inherit inputs; };
    markdownPreviewSystems = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    mkMarkdownPreviewDeps = system:
      let
        pkgs = import inputs.nixpkgs { inherit system; };
      in
      pkgs.callPackage ./home/modules/programs/markdown-preview-deps.nix { };
    mkLinuxHome = {
      system,
      homeModule,
      platformName,
      hostName,
    }:
      mkLinux {
        inherit system homeModule platformName hostName;
        systemModule = ./system/linux/hosts/ubuntu.nix;
        userName = envOr "DOTFILES_RUNTIME_USER" "teo";
        homeDirectory = envOr "DOTFILES_RUNTIME_HOME" "/home/teo";
      };
    macosConfig = mkDarwin {
      system = "aarch64-darwin";
      darwinModule = ./system/darwin/hosts/macos.nix;
      homeModule = ./home/hosts/macos.nix;
      platformName = "macos";
      hostName = "macos";
      userName = "teo";
      homeDirectory = "/Users/teo";
    };
    macosSystemOnlyConfig = mkDarwin {
      system = "aarch64-darwin";
      darwinModule = ./system/darwin/hosts/macos.nix;
      platformName = "macos";
      hostName = "macos";
      userName = "teo";
      homeDirectory = "/Users/teo";
    };
    macosHomeConfig = mkHome {
      system = "aarch64-darwin";
      hostModule = ./home/hosts/macos.nix;
      platformName = "macos";
      hostName = "macos";
      userName = "teo";
      homeDirectory = "/Users/teo";
    };
    linuxAarch64Config = mkLinuxHome {
      system = "aarch64-linux";
      homeModule = ./home/hosts/linux.nix;
      platformName = "linux";
      hostName = "linux";
    };
    linuxX86_64Config = mkLinuxHome {
      system = "x86_64-linux";
      homeModule = ./home/hosts/linux.nix;
      platformName = "linux";
      hostName = "linux";
    };
    dockerAarch64Config = mkLinuxHome {
      system = "aarch64-linux";
      homeModule = ./home/hosts/docker.nix;
      platformName = "docker";
      hostName = "docker";
    };
    dockerX86_64Config = mkLinuxHome {
      system = "x86_64-linux";
      homeModule = ./home/hosts/docker.nix;
      platformName = "docker";
      hostName = "docker";
    };
  in
  {
    darwinConfigurations = {
      "macos" = macosConfig;
    };

    homeConfigurations = {
      "macos" = macosHomeConfig;

      "linux" =
        if runtimeLinuxSystem == "x86_64-linux" then
          linuxX86_64Config
        else
          linuxAarch64Config;

      "docker" =
        if runtimeLinuxSystem == "x86_64-linux" then
          dockerX86_64Config
        else
          dockerAarch64Config;

      "linuxAarch64" = linuxAarch64Config;
      "linuxX86_64" = linuxX86_64Config;
      "dockerAarch64" = dockerAarch64Config;
      "dockerX86_64" = dockerX86_64Config;
    };

    packages = builtins.listToAttrs (map (system: {
      name = system;
      value = {
        nvim-markdown-preview-deps = mkMarkdownPreviewDeps system;
      } // (if system == "aarch64-darwin" then {
        macos-system = macosSystemOnlyConfig.config.system.build.toplevel;
      } else { });
    }) markdownPreviewSystems);
  };
}
