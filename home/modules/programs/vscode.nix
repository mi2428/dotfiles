{ platformFiles, ... }: {
  home.file = {
    "${platformFiles.vscode.settingsTarget}" = {
      force = true;
      source = ../../../home/files/config/vscode/settings.json;
    };
  };
}
