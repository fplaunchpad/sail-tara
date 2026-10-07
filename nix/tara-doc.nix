# The specification typeset from the model: a PDF, and the same document as AsciiDoc and HTML.
{
  justDerivation,
  sail,
  sailDocTables,
  asciidoctorSail,
  prettier,
  docFonts,
  pythonRuntime,
}:

justDerivation {
  pname = "tara-doc";
  fileset = [
    ../model
    ../doc
    ../tools
    ../.prettierrc.json
  ];
  nativeBuildInputs = [
    sail
    sailDocTables
    asciidoctorSail
    prettier
    pythonRuntime
  ];
  env = {
    TARA_PYTHON = pythonRuntime.interpreter;
    TARA_DOC_FONTS = "${docFonts}/fonts";
    TARA_DOC_PLUGIN = "${sailDocTables}/lib/sail-doc-tables/sail_doc_tables.cmxs";
  };
  recipes = [
    "doc::build"
    "doc::html"
  ];
  installPhase = ''
    install -Dm644 build/doc/tara.pdf "$out/share/doc/tara/tara.pdf"
    install -Dm644 build/doc/tara.html "$out/share/doc/tara/tara.html"
    install -Dm644 build/doc/main.adoc "$out/share/doc/tara/main.adoc"
    install -Dm644 build/doc/tara.json "$out/share/doc/tara/tara.json"
    install -Dm644 build/doc/tables.json "$out/share/doc/tara/tables.json"
    install -Dm644 build/doc/formats.adoc "$out/share/doc/tara/formats.adoc"
    install -Dm644 build/doc/opcodes.adoc "$out/share/doc/tara/opcodes.adoc"
    install -Dm644 build/doc/instructions.adoc "$out/share/doc/tara/instructions.adoc"
    install -Dm644 build/doc/notation.adoc "$out/share/doc/tara/notation.adoc"
    install -Dm644 build/doc/helpers.adoc "$out/share/doc/tara/helpers.adoc"
    install -d "$out/share/doc/tara/encodings"
    install -m644 build/doc/encodings/*.svg "$out/share/doc/tara/encodings/"
    install -Dm644 build/doc/styles.css "$out/share/doc/tara/styles.css"
    install -Dm644 build/doc/theme.yml "$out/share/doc/tara/theme.yml"
    install -Dm644 build/doc/cover.svg "$out/share/doc/tara/cover.svg"
    install -Dm644 build/doc/sections.rb "$out/share/doc/tara/sections.rb"
    install -Dm644 build/doc/table_widths.rb "$out/share/doc/tara/table_widths.rb"
    install -Dm644 "${docFonts}/fonts/Petrona-OFL.txt" "$out/share/doc/tara/fonts/Petrona-OFL.txt"
    install -Dm644 "${docFonts}/fonts/JetBrainsMono-OFL.txt" "$out/share/doc/tara/fonts/JetBrains-Mono-OFL.txt"
    install -m644 build/doc/fonts/*.ttf "$out/share/doc/tara/fonts/"
  '';
}
