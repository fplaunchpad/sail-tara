# The model's Rocq definitions, compiled with the proofs of their properties.
{
  justDerivation,
  bash,
  sail,
  rocqPackages,
  rocq-sail-stdpp,
}:

justDerivation {
  pname = "tara-rocq";
  fileset = [
    ../model
    ../proofs/rocq
  ];
  nativeBuildInputs = [
    bash
    sail
    rocqPackages.rocq-core
  ];
  buildInputs = [ rocq-sail-stdpp ];
  recipes = [ "rocq::build" ];
  installPhase = ''
    mkdir -p "$out/share/tara/rocq"
    cp build/rocq/*.v build/rocq/*.vo proofs/rocq/Tara/*.v "$out/share/tara/rocq/"
  '';
}
