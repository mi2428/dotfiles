{ inputs, lib, pkgs, ... }:
let
  markdownPreviewDeps = pkgs.callPackage ./markdown-preview-deps.nix { };
  linguaMotionPackages = inputs.lingua-motion.packages.${pkgs.system};
in {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = false;
    withPython3 = false;
    plugins = lib.optionals pkgs.stdenv.isDarwin [
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
}
