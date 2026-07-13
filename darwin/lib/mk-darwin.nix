{ inputs, self }:
{
  system,
  darwinModule,
  homeModule,
  hostName,
  userName,
  homeDirectory,
}:
inputs.nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = {
    inherit inputs self hostName userName homeDirectory;
  };
  modules = [
    darwinModule
    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {
        inherit inputs hostName userName homeDirectory;
      };
      home-manager.users.${userName}.imports = [ homeModule ];
      users.users.${userName}.home = homeDirectory;
    }
  ];
}
