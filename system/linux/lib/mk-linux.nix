{ inputs }:
{
  system,
  systemModule,
  homeModule,
  platformName,
  hostName,
  userName,
  homeDirectory,
}:
let
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = [
    systemModule
    homeModule
  ];
  extraSpecialArgs = {
    inherit inputs platformName hostName userName homeDirectory;
  };
}
