{ inputs, lib, pkgs, ... }:
let
  markdownPreviewDeps = pkgs.callPackage ./markdown-preview-deps.nix { };
  linguaMotionPackages = inputs.lingua-motion.packages.${pkgs.system};
  luamigemo = pkgs.vimUtils.buildVimPlugin {
    pname = "luamigemo";
    version = "1.4.1";
    src = inputs.luamigemo;
  };
in {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = false;
    withPython3 = false;
    plugins = [ luamigemo ] ++ lib.optionals pkgs.stdenv.isDarwin [
      linguaMotionPackages.lingua-motion
    ];
    extraPackages = lib.optionals pkgs.stdenv.isDarwin [
      linguaMotionPackages.lingua-motion-helper
    ];
  };

  xdg.configFile."nvim" = {
    source = ../../../home/files/config/nvim;
    recursive = true;
  };

  xdg.dataFile."nvim/markdown-preview/mermaid.min.js".source =
    "${markdownPreviewDeps}/share/mermaid/mermaid.min.js";
  xdg.dataFile."nvim/migemo-compact-dict".source =
    "${inputs.migemo-dict}/migemo-compact-dict";
}
