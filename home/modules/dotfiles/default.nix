{ lib, ... }:
let
  inherit (lib) mkOption types;
in {
  options.dotfiles.platform = {
    fish.extraFiles = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional Fish config files enabled for the current host.";
    };

    git = mkOption {
      type = types.path;
      description = "Host-specific Git config source.";
    };

    tmux = {
      cpu = mkOption {
        type = types.path;
        description = "Host-specific tmux CPU status script.";
      };

      mem = mkOption {
        type = types.path;
        description = "Host-specific tmux memory status script.";
      };
    };

    zsh.overrides = mkOption {
      type = types.attrsOf types.path;
      default = { };
      description = "Host-specific Zsh fragment overrides keyed by filename.";
    };
  };
}
