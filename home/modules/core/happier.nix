{
  config,
  lib,
  pkgs,
  platformName,
  ...
}:
let
  happierInstaller = pkgs.fetchurl {
    url = "https://happier.dev/install";
    hash = "sha256-L1MpaU99jRleCwOfcTT95PvSZ5SZa0Y7RwyTCJqOgeo=";
  };
in
lib.mkIf (platformName != "docker") {
  # The official installer owns ~/.happier and the shim in ~/.local/bin.
  # Skip the daemon here: `happier setup` asks for the relay and installs the
  # service after the user has signed in.
  home.activation.installHappier = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    happier_bin="${config.home.homeDirectory}/.local/bin/happier"
    if ! "$happier_bin" --version >/dev/null 2>&1; then
      PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
        HAPPIER_CHANNEL=stable \
        HAPPIER_NONINTERACTIVE=1 \
        HAPPIER_NO_PATH_UPDATE=1 \
        HAPPIER_WITH_DAEMON=0 \
        HAPPIER_INSTALL_DIR="${config.home.homeDirectory}/.happier" \
        HAPPIER_BIN_DIR="${config.home.homeDirectory}/.local/bin" \
        bash "${happierInstaller}"
      test -x "$happier_bin" || {
        echo 'Happier installation did not create the expected binary: '"$happier_bin" >&2
        exit 1
      }
    fi
  '';
}
