# Checks beyond building the packages.
{
  lib,
  runCommand,
  justDerivation,
  sail,
  jq,
  clang-tools,
  ocamlPackages,
  taracpu,
  tara-c,
  tara-ocaml,
  pythonTest,
  pythonDevTools,
}:

let
  # The Python sources and their configuration, writable for the tools' caches.
  pythonSource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../pyproject.toml
      ../tools
      ../typings
      ../tests
    ];
  };
in
{
  # The emulator test suite: both emulators against the reference model.
  tests =
    runCommand "tests"
      {
        nativeBuildInputs = [ pythonTest ];
        env.PYTHONPATH = "${taracpu}/share/taracpu";
      }
      ''
        cp -r ${pythonSource}/. . && chmod -R u+w .
        export HOME="$TMPDIR"
        pytest -p no:cacheprovider --hypothesis-profile=ci \
          --emulator=${lib.getExe tara-c} \
          --emulator=${lib.getExe tara-ocaml}
        touch "$out"
      '';

  # Formatting and line width of the Sail, C and OCaml sources.
  lint = justDerivation {
    pname = "lint";
    fileset = [
      ../model
      ../emulator
      ../lean
    ];
    nativeBuildInputs = [
      sail
      jq
      clang-tools
      ocamlPackages.ocamlformat
    ];
    recipes = [
      "model::lint"
      "c::lint"
      "ocaml::lint"
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
