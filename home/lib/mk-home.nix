{ inputs }:
{
  system,
  hostModule,
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
  modules = [ hostModule ];
  extraSpecialArgs = {
    inherit inputs;
    inherit platformName hostName userName homeDirectory;
  };
}
