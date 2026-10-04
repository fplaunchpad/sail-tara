# Development shell: every toolchain the justfile recipes use.
{
  lib,
  mkShell,
  sail,
  z3,
  just,
  gmp,
  zlib,
  ocamlPackages,
  rocqPackages,
  rocq-sail-stdpp,
  lean,
  python,
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
    nixfmt
    # C emulator and the Sail test suite.
    gmp
    zlib
    # OCaml emulator (libsail is part of the sail package).
    ocamlPackages.ocaml
    ocamlPackages.dune_3
    ocamlPackages.findlib
    # Rocq and Lean extraction.
    rocqPackages.rocq-core
    lean
    # Python tooling: locked dev tools via uv; Pyright needs Node.
    python
    uv
    nodejs
    tara-tools
  ];

  buildInputs = [
    sail
    rocq-sail-stdpp
  ];

  env = {
    TARACPU = "${taracpu}/share/taracpu";
    UV_PYTHON_DOWNLOADS = "never";
    UV_PYTHON = lib.getExe python;
    UV_PROJECT_ENVIRONMENT = ".venv";
    PYRIGHT_PYTHON_GLOBAL_NODE = "true";
    PYRIGHT_PYTHON_NODEJS_WHEEL = "false";
  };
}
