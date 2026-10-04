# The specification typeset from the model, as a PDF.
{
  justDerivation,
  sail,
  texlive,
}:

justDerivation {
  pname = "tara-doc";
  fileset = [
    ../model
    ../doc
  ];
  nativeBuildInputs = [
    sail
    texlive
  ];
  recipes = [ "doc::build" ];
  installPhase = ''
    install -Dm644 build/doc/tara.pdf "$out/share/doc/tara/tara.pdf"
  '';
}
