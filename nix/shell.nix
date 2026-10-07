# Development shell: every toolchain the justfile recipes use.
{
  lib,
  mkShell,
  sail,
  sailDocTables,
  z3,
  just,
  jq,
  gmp,
  clang-tools,
  cmake,
  ninja,
  verilator,
  cli11,
  zlib,
  ocamlPackages,
  rocqPackages,
  rocq-sail-stdpp,
  lean,
  lean-sail,
  asciidoctorSail,
  prettier,
  docFonts,
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
    sailDocTables
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
    verilator
    cli11
    # OCaml emulator (libsail is part of the sail package).
    ocamlPackages.ocaml
    ocamlPackages.dune_3
    ocamlPackages.findlib
    ocamlPackages.ocamlformat
    # Rocq and Lean extraction, and the typeset specification.
    rocqPackages.rocq-core
    lean
    asciidoctorSail
    prettier
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
    ocamlPackages.angstrom
    ocamlPackages.core_unix
    ocamlPackages.ppx_jane
    ocamlPackages.ppx_yojson_conv
  ];

  env = {
    TARACPU = "${taracpu}/share/taracpu";
    # TARA Studio's modules (src.*), for the reference model and the tests.
    PYTHONPATH = "${taracpu}/share/taracpu";
    # The interpreter of the test suite, with its dependencies; Pyright resolves imports with it.
    TARA_PYTHON = pythonTest.interpreter;
    LEAN_SAIL = "${lean-sail}";
    TARA_DOC_FONTS = "${docFonts}/fonts";
    TARA_DOC_PLUGIN = "${sailDocTables}/lib/sail-doc-tables/sail_doc_tables.cmxs";
    UV_PYTHON_DOWNLOADS = "never";
    UV_PYTHON = lib.getExe python;
    UV_PROJECT_ENVIRONMENT = ".venv";
    PYRIGHT_PYTHON_GLOBAL_NODE = "true";
    PYRIGHT_PYTHON_NODEJS_WHEEL = "false";
  };
}
