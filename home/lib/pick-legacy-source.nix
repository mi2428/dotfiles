{ hostName }:
{ baseRoot, overlays ? { } }:
relativePath:
let
  overlayRoot = overlays.${hostName} or null;
  overlayPath =
    if overlayRoot == null then null else overlayRoot + "/${relativePath}";
in
if overlayPath != null && builtins.pathExists overlayPath then
  overlayPath
else
  baseRoot + "/${relativePath}"
