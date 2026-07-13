{ hostName, lib, ... }:
let
  baseRelativeFiles = [
    "config.fish"
    "fish_plugins"
    "conf.d/05_catppuccin_theme.fish"
    "conf.d/10_general.fish"
    "conf.d/11_starship.fish"
    "conf.d/12_general_path.fish"
    "conf.d/13_zoxide.fish"
    "conf.d/14_fzf_git.fish"
    "conf.d/15_fzf_theme.fish"
    "conf.d/20_aliases.fish"
    "conf.d/21_functions.fish"
    "conf.d/40_grc.fish"
    "functions/fish_title.fish"
    "functions/fish_user_key_bindings.fish"
  ];
  hostExtraFiles = {
    macos = [
      "conf.d/22_aliases.fish"
    ];
  };
  relativeFiles = baseRelativeFiles ++ (hostExtraFiles.${hostName} or [ ]);
  pickSource = import ../../lib/pick-legacy-source.nix { inherit hostName; } {
    baseRoot = ../../../home/files/config/fish;
    overlays = {
      macos = ../../../home/files/hosts/macos/fish;
    };
  };
  fishFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair "fish/${relativePath}" {
        source = pickSource relativePath;
      })
    relativeFiles);
in {
  xdg.configFile = fishFiles;
}
