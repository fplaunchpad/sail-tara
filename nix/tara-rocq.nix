# The model's Rocq definitions, compiled with the smoke test.
{
  justDerivation,
  sail,
  rocqPackages,
  rocq-sail-stdpp,
}:

justDerivation {
  pname = "tara-rocq";
  fileset = [
    ../model
    ../rocq
  ];
  nativeBuildInputs = [
    sail
    rocqPackages.rocq-core
  ];
  buildInputs = [ rocq-sail-stdpp ];
  recipes = [ "rocq" ];
  installPhase = ''
    mkdir -p "$out/share/tara/rocq"
    cp build/rocq/*.v build/rocq/*.vo "$out/share/tara/rocq/"
  '';
}
