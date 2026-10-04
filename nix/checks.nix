# Checks beyond building the packages.
{
  lib,
  runCommand,
  justDerivation,
  sail,
  asciidoctorSail,
  sailDocTables,
  docFonts,
  prettier,
  just,
  jq,
  clang-tools,
  cmake,
  ninja,
  gmp,
  zlib,
  ocamlPackages,
  taracpu,
  tara-c,
  tara-ocaml,
  pythonTest,
  pythonDevTools,
}:

let
  # The Python sources and their configuration, writable for the tools' caches. The tests of the
  # specification build it with the documentation recipes, in a copy of these sources.
  pythonSource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../pyproject.toml
      ../tools
      ../typings
      ../tests
      ../model
      ../doc
      ../justfile
      ../just
      ../.prettierrc.json
    ];
  };
in
{
  # The test suite: both emulators against the reference model, and the specification written
  # from the model.
  tests =
    runCommand "tests"
      {
        nativeBuildInputs = [
          pythonTest
          sail
          asciidoctorSail
          sailDocTables
          prettier
          just
        ];
        env = {
          PYTHONPATH = "${taracpu}/share/taracpu";
          TARA_PYTHON = pythonTest.interpreter;
          TARA_DOC_PLUGIN = "${sailDocTables}/lib/sail-doc-tables/sail_doc_tables.cmxs";
          TARA_DOC_FONTS = "${docFonts}/fonts";
        };
      }
      ''
        cp -r ${pythonSource}/. . && chmod -R u+w .
        export HOME="$TMPDIR"
        pytest -p no:cacheprovider --hypothesis-profile=ci \
          --emulator=${lib.getExe tara-c} \
          --emulator=${lib.getExe tara-ocaml}
        touch "$out"
      '';

  # Formatting and line width of the Sail, C, OCaml, Rocq and Lean sources.
  lint = justDerivation {
    pname = "lint";
    fileset = [
      ../model
      ../emulator
      ../proofs/lean
      ../proofs/rocq
      ../doc
      ../tools/sail-doc
    ];
    nativeBuildInputs = [
      sail
      sailDocTables
      jq
      clang-tools
      cmake
      ninja
      ocamlPackages.ocamlformat
      prettier
    ];
    # c::lint builds the emulator for clang-tidy's compile commands.
    buildInputs = [
      gmp
      zlib
    ];
    dontUseCmakeConfigure = true;
    dontUseNinjaBuild = true;
    dontUseNinjaInstall = true;
    dontUseNinjaCheck = true;
    recipes = [
      "model::lint"
      "c::lint"
      "ocaml::lint"
      "sail-doc::lint"
      "rocq::lint"
      "lean::lint"
      "doc::lint"
    ];
    installPhase = "touch $out";
  };

  # Ruff, Black and Pyright, at the releases pyproject.toml pins.
  python-lint =
    runCommand "python-lint"
      {
        nativeBuildInputs = [ pythonTest ] ++ pythonDevTools;
      }
      ''
        cp -r ${pythonSource}/. . && chmod -R u+w .
        export HOME="$TMPDIR"
        ruff check --no-cache tools typings tests
        black --check tools typings tests
        pyright
        touch "$out"
      '';
}
