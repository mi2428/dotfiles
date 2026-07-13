{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    profiles.default = {
      extensions = with pkgs.vscode-extensions.catppuccin; [
        catppuccin-vsc
        catppuccin-vsc-icons
      ];
    };
  };

  xdg.configFile."Code/User/settings.json" = {
    force = true;
    source = ../../../home/files/config/vscode/settings.json;
  };

  home.file."Library/Application Support/Code/User/settings.json" = {
    force = true;
    source = ../../../home/files/config/vscode/settings.json;
  };
}
