# An external Sail plugin deriving instruction tables from the typed model.
{
  justDerivation,
  sail,
  ocamlPackages,
}:

justDerivation {
  pname = "sail-doc-tables";
  fileset = [ ../tools/sail-doc ];
  nativeBuildInputs = [
    sail
    ocamlPackages.ocaml
    ocamlPackages.dune_3
    ocamlPackages.findlib
  ];
  buildInputs = [
    sail
    ocamlPackages.core
    ocamlPackages.angstrom
    ocamlPackages.ppx_jane
    ocamlPackages.ppx_yojson_conv
  ];
  recipes = [ "sail-doc::build" ];
  installPhase = ''
    install -Dm644 build/sail-doc/sail_doc_tables.cmxs \
      "$out/lib/sail-doc-tables/sail_doc_tables.cmxs"
  '';
  meta.description = "Instruction table metadata derived from Sail's typed mappings and codecs";
}
