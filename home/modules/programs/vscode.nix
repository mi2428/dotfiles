{ hostName, ... }:
let
  settingsTarget =
    if hostName == "macos" then
      "Library/Application Support/Code/User/settings.json"
    else
      ".config/Code/User/settings.json";
in {
  home.file = {
    "${settingsTarget}" = {
      force = true;
      source = ../../../home/files/config/vscode/settings.json;
    };
  };
}
