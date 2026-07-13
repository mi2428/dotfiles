{ inputs, self }:
{
  system,
  darwinModule,
  homeModule,
  platformName,
  hostName,
  userName,
  homeDirectory,
}:
inputs.nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = {
    inherit inputs self platformName hostName userName homeDirectory;
  };
  modules = [
    darwinModule
    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.backupFileExtension = "hm-backup";
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = false;
      home-manager.extraSpecialArgs = {
        inherit inputs platformName hostName userName homeDirectory;
      };
      home-manager.users.${userName}.imports = [ homeModule ];
      users.users.${userName}.home = homeDirectory;
    }
  ];
}
