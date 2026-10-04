# Checks beyond building the packages.
{
  lib,
  runCommand,
  justDerivation,
  sail,
  gmp,
  zlib,
  jq,
  clang-tools,
  ocamlPackages,
  pythonRuntime,
  pythonDevTools,
}:

{
  # The model's Sail unit tests, through the C backend.
  model = justDerivation {
    pname = "model-tests";
    fileset = [
      ../model
      ../tests/model
    ];
    nativeBuildInputs = [ sail ];
    buildInputs = [
      gmp
      zlib
    ];
    recipes = [ "model::test" ];
    installPhase = "touch $out";
  };

  # Formatting and line width of the Sail, C and OCaml sources.
  lint = justDerivation {
    pname = "lint";
    fileset = [
      ../model
      ../emulator
      ../tests/model
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
        src = lib.fileset.toSource {
          root = ../.;
          fileset = lib.fileset.unions [
            ../pyproject.toml
            ../tools
            ../typings
          ];
        };
        nativeBuildInputs = [ pythonRuntime ] ++ pythonDevTools;
      }
      ''
        cp -r "$src"/. . && chmod -R u+w .
        export HOME="$TMPDIR"
        ruff check --no-cache tools typings
        black --check tools typings
        pyright
        touch "$out"
      '';
}
