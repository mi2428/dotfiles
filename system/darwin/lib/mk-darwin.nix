{ inputs, self }:
{
  system,
  darwinModule,
  homeModule ? null,
  platformName,
  hostName,
  userName,
  homeDirectory,
}:
let
  homeManagerModules =
    if homeModule == null then
      [ ]
    else
      [
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
in
inputs.nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = {
    inherit inputs self platformName hostName userName homeDirectory;
  };
  modules = [ darwinModule ] ++ homeManagerModules;
}
