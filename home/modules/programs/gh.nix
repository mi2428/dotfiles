{ inputs, pkgs, ... }:
let
  ghInboxCargo = builtins.fromTOML (builtins.readFile "${inputs.gh-inbox}/Cargo.toml");
  ghInbox = pkgs.rustPlatform.buildRustPackage {
    pname = "gh-inbox";
    inherit (ghInboxCargo.package) version;
    src = inputs.gh-inbox;
    cargoLock.lockFile = "${inputs.gh-inbox}/Cargo.lock";
  };
in
{
  programs.gh = {
    enable = true;
    extensions = [
      pkgs.gh-dash
      ghInbox
    ];
    settings = {
      git_protocol = "https";
      prompt = "enabled";
      prefer_editor_prompt = "disabled";
      aliases.co = "pr checkout";
      color_labels = "disabled";
      accessible_colors = "disabled";
      accessible_prompter = "disabled";
      spinner = "enabled";
    };
  };
}
