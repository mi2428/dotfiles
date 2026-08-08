{ pkgs, ... }:
let
  markdownPreviewDeps = pkgs.callPackage ./markdown-preview-deps.nix { };
in {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = false;
    withPython3 = false;
  };

  xdg.configFile."nvim" = {
    source = ../../../home/files/config/nvim;
    recursive = true;
  };

  xdg.dataFile."nvim/markdown-preview/mermaid.min.js".source =
    "${markdownPreviewDeps}/share/mermaid/mermaid.min.js";
}
