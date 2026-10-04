# Checks beyond the packages (whose check phases run the golden tests).
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
  # The Sail test suite, through the C backend.
  sail-tests = justDerivation {
    pname = "sail-tests";
    fileset = [
      ../model
      ../tests
    ];
    nativeBuildInputs = [ sail ];
    buildInputs = [
      gmp
      zlib
    ];
    recipes = [ "test" ];
    installPhase = "touch $out";
  };

  # Formatting and line width of the Sail, C and OCaml sources.
  lint = justDerivation {
    pname = "lint";
    fileset = [
      ../model
      ../emulator
      ../tests
    ];
    nativeBuildInputs = [
      sail
      jq
      clang-tools
      ocamlPackages.ocamlformat
    ];
    recipes = [ "lint" ];
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
