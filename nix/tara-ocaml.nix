# The OCaml emulator, built from the model's OCaml output.
{
  justDerivation,
  sail,
  ocamlPackages,
}:

justDerivation {
  pname = "tara-ocaml";
  fileset = [
    ../model
    ../emulator/host.sail
    ../emulator/ocaml
  ];
  nativeBuildInputs = [
    sail
    ocamlPackages.ocaml
    ocamlPackages.dune_3
    ocamlPackages.findlib
  ];
  buildInputs = [
    sail
    ocamlPackages.core
    ocamlPackages.core_unix
    ocamlPackages.ppx_jane
  ];
  recipes = [ "ocaml::build" ];
  installPhase = ''
    install -Dm755 build/ocaml/_build/default/src/main.exe "$out/bin/tara-ocaml"
  '';
  meta = {
    description = "TARA emulator built from the Sail model's OCaml output";
    mainProgram = "tara-ocaml";
  };
}
