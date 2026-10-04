# Use the locked Lean manifest with our hostPlatform compatibility fix.
{ lean4Nix, toolchain }:

let
  version = builtins.match "^[[:space:]]*leanprover/lean4:([a-zA-Z0-9\\-\\.]+)[[:space:]]*$" (
    builtins.readFile toolchain
  );
  tag =
    if version == null then
      throw "lean-toolchain must name a stable leanprover/lean4 release"
    else
      builtins.head version;
  manifest = import "${lean4Nix}/manifests/${tag}.nix";
in
final: prev:
(manifest.overlay or (_: _: { })) final prev
// {
  lean = (final.callPackage ./lean4/toolchain.nix { inherit lean4Nix; }).fetchBinaryLean manifest;
}
