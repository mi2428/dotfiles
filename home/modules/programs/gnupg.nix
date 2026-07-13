{ config, lib, pkgs, ... }:
let
  currentPrefix = if pkgs.stdenv.hostPlatform.isAarch64 then "/opt/homebrew" else "/usr/local";
  mkAgentConf = prefix: ''
    pinentry-program ${prefix}/bin/pinentry-mac
  '';
in {
  home.file = {
    ".gnupg/gpg-agent.conf".text = mkAgentConf currentPrefix;
    ".gnupg/gpg-agent.conf.apple".text = mkAgentConf "/opt/homebrew";
    ".gnupg/gpg-agent.conf.intel".text = mkAgentConf "/usr/local";
  };

  home.activation.gnupgPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "${config.home.homeDirectory}/.gnupg" ]; then
      chmod 700 "${config.home.homeDirectory}/.gnupg"
    fi
  '';
}
