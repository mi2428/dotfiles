{ ... }:
let
  userName =
    let
      value = builtins.getEnv "DOTFILES_USER";
    in
    if value != "" then value else "teo";
  homeDirectory =
    let
      value = builtins.getEnv "DOTFILES_HOME";
    in
    if value != "" then value else "/Users/teo";
in {
  imports = [
    ../profiles/base.nix
    ../profiles/os/macos.nix
    ../profiles/role/desktop.nix
  ];

  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
}
