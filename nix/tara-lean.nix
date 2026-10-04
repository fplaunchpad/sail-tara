# The model's Lean definitions, built against the pinned lean-sail.
{
  justDerivation,
  sail,
  lean,
  lean-sail,
}:

justDerivation {
  pname = "tara-lean";
  fileset = [
    ../model
    ../lean
  ];
  nativeBuildInputs = [
    sail
    lean
  ];
  env.LEAN_SAIL = lean-sail;
  recipes = [ "lean::build" ];
  installPhase = ''
    mkdir -p "$out/share/tara/lean"
    cp -r build/lean/Tara/Tara.lean build/lean/Tara/Tara "$out/share/tara/lean/"
  '';
}
