{ config, lib, pkgs, ... }:
let
  inherit (config.dotfiles) platform;
  catppuccinFish = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "fish";
    rev = "5fc5ae9c2ec22eb376cb03ce76f0d262a38960f3";
    hash = "sha256-3KNWYXfOMzZovdjwjBpjSH8cVlD4CO2QmQcCyQE4Dac=";
  };
  fzfGitSource = pkgs.fetchFromGitHub {
    owner = "junegunn";
    repo = "fzf-git.sh";
    rev = "fdf632c53262dfcc44fc09d591e462e9f8fcae83";
    hash = "sha256-3ho7Kn84q36bj9N+Nj+5XEdkXIN4xwYk7h7g/ou3TRM=";
  };
  baseRelativeFiles = [
    "conf.d/05_catppuccin_theme.fish"
    "conf.d/10_general.fish"
    "conf.d/12_general_path.fish"
    "conf.d/13_zoxide.fish"
    "conf.d/14_fzf_git.fish"
    "conf.d/15_fzf_theme.fish"
    "conf.d/16_starship.fish"
    "conf.d/20_aliases.fish"
    "conf.d/21_functions.fish"
    "conf.d/40_grc.fish"
    "functions/fish_title.fish"
    "functions/fish_user_key_bindings.fish"
  ];
  relativeFiles = baseRelativeFiles ++ platform.fish.extraFiles;
  sourceFor = relativePath:
    if builtins.hasAttr relativePath platform.fish.overrides then
      platform.fish.overrides.${relativePath}
    else
      ../../../home/files/config/fish/${relativePath};
  fishFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair "fish/${relativePath}" {
        source = sourceFor relativePath;
      })
    relativeFiles);
in {
  programs.fish = {
    enable = true;
    plugins = [
      {
        name = "catppuccin-fish";
        src = catppuccinFish;
      }
      {
        name = "fzf-fish";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
    ];
  };

  xdg.configFile = fishFiles // {
    "fish/config.fish" = lib.mkForce {
      source = ../../../home/files/config/fish/config.fish;
    };
    "fish/fish_plugins".source = ../../../home/files/config/fish/fish_plugins;
  };

  home.activation.removeLegacyOmfFishConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rm -f "${config.home.homeDirectory}/.config/fish/conf.d/omf.fish"
  '';

  xdg.dataFile."fzf-git" = {
    source = fzfGitSource;
  };
}
