# Development shell: every toolchain the justfile recipes use.
{
  lib,
  mkShell,
  sail,
  z3,
  just,
  jq,
  gmp,
  clang-tools,
  cmake,
  ninja,
  zlib,
  ocamlPackages,
  rocqPackages,
  rocq-sail-stdpp,
  lean,
  lean-sail,
  texlive,
  asciidoctor,
  python,
  pythonTest,
  uv,
  nodejs,
  taracpu,
  tara-tools,
  nixfmt,
}:

mkShell {
  packages = [
    sail
    z3
    just
    jq
    nixfmt
    # C emulator and the Sail test suite.
    gmp
    zlib
    clang-tools
    cmake
    ninja
    # OCaml emulator (libsail is part of the sail package).
    ocamlPackages.ocaml
    ocamlPackages.dune_3
    ocamlPackages.findlib
    ocamlPackages.ocamlformat
    # Lem definitions and their OCaml extraction.
    ocamlPackages.lem
    # Rocq and Lean extraction, and the typeset specification.
    rocqPackages.rocq-core
    lean
    texlive
    asciidoctor
    # Python tooling: locked dev tools via uv; Pyright needs Node.
    python
    uv
    nodejs
    tara-tools
  ];

  # Libraries found through setup hooks (OCAMLPATH, ROCQPATH).
  buildInputs = [
    sail
    rocq-sail-stdpp
    ocamlPackages.core
    ocamlPackages.core_unix
    ocamlPackages.ppx_jane
  ];

  env = {
    TARACPU = "${taracpu}/share/taracpu";
    # TARA Studio's modules (src.*), for the reference model and the tests.
    PYTHONPATH = "${taracpu}/share/taracpu";
    # The interpreter of the test suite, with its dependencies; Pyright resolves imports with it.
    TARA_PYTHON = pythonTest.interpreter;
    LEAN_SAIL = "${lean-sail}";
    UV_PYTHON_DOWNLOADS = "never";
    UV_PYTHON = lib.getExe python;
    UV_PROJECT_ENVIRONMENT = ".venv";
    PYRIGHT_PYTHON_GLOBAL_NODE = "true";
    PYRIGHT_PYTHON_NODEJS_WHEEL = "false";
  };
}
