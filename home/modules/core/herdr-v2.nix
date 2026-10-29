{
  config,
  lib,
  pkgs,
  platformName,
  ...
}:
let
  patchedHerdr = pkgs.herdr.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../../files/herdr/opencode-v2.patch ];
    postInstall = (old.postInstall or "") + ''
      install -Dm644 src/integration/assets/opencode/tui.js "$out/share/herdr/opencode/tui.js"
      install -Dm644 src/integration/assets/opencode/herdr-tui-session.js "$out/share/herdr/herdr-tui-session.js"
      install -Dm644 src/integration/assets/opencode/herdr-agent-state.js "$out/share/herdr/opencode/herdr-agent-state.js"
    '';
  });
in
{
  options.dotfiles.herdr.package = lib.mkOption {
    type = lib.types.package;
    default = patchedHerdr;
    description = "Herdr built from the pinned v0.9.5 source with the local OpenCode V2 integration patch.";
  };

  config = lib.mkIf (platformName != "docker") {
    home.packages = [ config.dotfiles.herdr.package ];
    home.file.".local/bin/herdr" = {
      source = "${config.dotfiles.herdr.package}/bin/herdr";
    };
  };
}
