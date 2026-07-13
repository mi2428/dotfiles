{ ... }:
let
  settings = builtins.fromJSON (
    builtins.readFile ../../../home/files/config/vscode/settings.json
  );
in {
  programs.vscode = {
    enable = true;
    profiles.default.userSettings = settings;
  };
}
