{ config, lib, pkgs, ... }:
let
  currentPinentry = "${pkgs.pinentry_mac}/bin/pinentry-mac";
  mkAgentConf = pinentryProgram: ''
    pinentry-program ${pinentryProgram}
  '';
in {
  home.file = {
    ".gnupg/gpg-agent.conf" = {
      force = true;
      text = mkAgentConf currentPinentry;
    };
    ".gnupg/gpg-agent.conf.apple" = {
      force = true;
      text = mkAgentConf "/opt/homebrew/bin/pinentry-mac";
    };
    ".gnupg/gpg-agent.conf.intel" = {
      force = true;
      text = mkAgentConf "/usr/local/bin/pinentry-mac";
    };
  };

  home.activation.gnupgPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "${config.home.homeDirectory}/.gnupg" ]; then
      chmod 700 "${config.home.homeDirectory}/.gnupg"
    fi
  '';
}
