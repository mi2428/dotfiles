{ lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
in {
  options.dotfiles.platform = {
    fish.extraFiles = mkOption {
      type = types.listOf types.str;
      default = lib.optionals pkgs.stdenv.isDarwin [ "conf.d/22_aliases.fish" ];
      description = "Additional Fish config files enabled for the current host.";
    };

    fish.overrides = mkOption {
      type = types.attrsOf types.path;
      default =
        if pkgs.stdenv.isDarwin then
          {
            "conf.d/12_general_path.fish" = ../../files/config/fish/conf.d/12_general_path.macos.fish;
          }
        else
          { };
      description = "Host-specific Fish config sources keyed by relative path.";
    };

    git = mkOption {
      type = types.path;
      default =
        if pkgs.stdenv.isDarwin then
          ../../files/git/gitconfig.macos
        else
          ../../files/git/gitconfig;
      description = "Host-specific Git config source.";
    };

    tmux = {
      cpu = mkOption {
        type = types.path;
        default =
          if pkgs.stdenv.isDarwin then
            ../../files/tmux/scripts/cpu.macos.sh
          else
            ../../files/tmux/scripts/cpu.sh;
        description = "Host-specific tmux CPU status script.";
      };

      mem = mkOption {
        type = types.path;
        default =
          if pkgs.stdenv.isDarwin then
            ../../files/tmux/scripts/mem.macos.sh
          else
            ../../files/tmux/scripts/mem.sh;
        description = "Host-specific tmux memory status script.";
      };
    };
  };
}
