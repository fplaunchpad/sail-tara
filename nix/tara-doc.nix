# The specification typeset from the model: a PDF, and the same document as AsciiDoc and HTML.
{
  justDerivation,
  sail,
  texlive,
  asciidoctor,
  pythonRuntime,
}:

justDerivation {
  pname = "tara-doc";
  fileset = [
    ../model
    ../doc
    ../tools
  ];
  nativeBuildInputs = [
    sail
    texlive
    asciidoctor
    pythonRuntime
  ];
  # The interpreter that just/doc.just runs the generator of the document with.
  env.TARA_PYTHON = pythonRuntime.interpreter;
  recipes = [
    "doc::build"
    "doc::html"
  ];
  installPhase = ''
    install -Dm644 build/doc/tara.pdf "$out/share/doc/tara/tara.pdf"
    install -Dm644 build/doc/tara.html "$out/share/doc/tara/tara.html"
    install -Dm644 build/doc/tara.adoc "$out/share/doc/tara/tara.adoc"
  '';
}
