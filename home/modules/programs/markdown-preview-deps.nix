{
  comrak,
  fetchurl,
  nodejs,
  stdenvNoCC,
  symlinkJoin,
}:
let
  mermaidBundle = stdenvNoCC.mkDerivation {
    pname = "mermaid-browser-bundle";
    version = "11.16.1";
    src = fetchurl {
      url = "https://registry.npmjs.org/mermaid/-/mermaid-11.16.1.tgz";
      hash = "sha256-69mIUREJLHjO/Hmnb2wdw07VuDSwKujzOCJ855wAPeQ=";
    };
    sourceRoot = "package";
    installPhase = ''
      runHook preInstall
      install -Dm0444 dist/mermaid.min.js "$out/share/mermaid/mermaid.min.js"
      runHook postInstall
    '';
  };
in
symlinkJoin {
  name = "nvim-markdown-preview-deps";
  paths = [
    nodejs
    comrak
    mermaidBundle
  ];
}
