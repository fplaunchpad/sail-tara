# The model's Lem definitions, typechecked against Sail's Lem library, and the smoke test that runs
# the manual's Fibonacci program on their OCaml extraction.
{
  justDerivation,
  sail,
  ocamlPackages,
}:

justDerivation {
  pname = "tara-lem";
  fileset = [
    ../model
    ../lem
  ];
  nativeBuildInputs = [
    sail
    ocamlPackages.lem
    ocamlPackages.ocaml
    ocamlPackages.dune_3
    ocamlPackages.findlib
  ];
  # Lem's OCaml library (lem_zarith), and Core for the smoke test.
  buildInputs = [
    ocamlPackages.lem
    ocamlPackages.core
    ocamlPackages.ppx_jane
  ];
  recipes = [ "lem::build" ];
  checkRecipes = [ "lem::smoke" ];
  installPhase = ''
    mkdir -p "$out/share/tara/lem"
    cp build/lem/*.lem "$out/share/tara/lem/"
  '';
}
