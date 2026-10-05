# Per-system outputs for the TARA toolchain.
{ pkgs }:

let
  inherit (pkgs) lib;
  # pyproject.toml pins the Python dependencies (runtime and development) to the
  # releases nixpkgs provides, so uv and the Nix checks run the same code.
  pyproject = lib.importTOML ../pyproject.toml;
  pinnedPackage =
    packages: requirement:
    let
      pin = builtins.match "([A-Za-z0-9_.-]+)==(.+)" requirement;
      package = packages.${lib.elemAt pin 0};
      version = lib.elemAt pin 1;
    in
    if pin == null then
      throw "pyproject.toml: pin ${requirement} with =="
    else if package.version != version then
      throw "pyproject.toml pins ${requirement}; nixpkgs has ${package.version}"
    else
      package;
  scope = lib.makeScope pkgs.newScope (self: {
    ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_5;
    rocqPackages = pkgs.rocqPackages_9_3;
    python = pkgs.python315;
    pythonRuntime = self.python.withPackages (
      ps: map (pinnedPackage ps) pyproject.project.dependencies
    );
    pythonDevTools = map (pinnedPackage pkgs) pyproject.dependency-groups.dev;
    # The runtime and the test suite's dependencies: the interpreter of the tests and of Pyright.
    # Hypothesis's own test suite fails on the Python 3.15 release candidate (deprecation
    # warnings raised as errors); the library itself works, so its tests are skipped.
    pythonTest = self.python.withPackages (
      ps:
      map (pinnedPackage (
        ps // { hypothesis = ps.hypothesis.overridePythonAttrs { doCheck = false; }; }
      )) (pyproject.project.dependencies ++ pyproject.tool.tara.test-dependencies)
    );

    sail = self.callPackage ./sail.nix { };
    # GCC 16 defaults to C++20, but nixpkgs' SystemC library exports its C++17 API guard.
    # Keep Verilator 5.052's SystemC smoke tests on the same standard as that library.
    verilator = pkgs.verilator.overrideAttrs (previous: {
      env = previous.env // {
        NIX_CFLAGS_COMPILE = "-std=c++17";
      };
    });
    rocq-sail-stdpp = self.rocqPackages.callPackage ./rocq-sail-stdpp.nix { };
    taracpu = self.callPackage ./taracpu.nix { };
    lean-sail = self.callPackage ./lean-sail.nix { };
    asciidoctorSail = self.callPackage ./asciidoctor-sail.nix { };
    docFonts = self.callPackage ./doc-fonts.nix { };
    justDerivation = self.callPackage ./just-derivation.nix { };
    sailDocTables = self.callPackage ./sail-doc-tables.nix { };

    tara-tools = self.callPackage ./tara-tools.nix { };
    tara-c = self.callPackage ./tara-c.nix { };
    tara-verilator = self.callPackage ./tara-verilator.nix { };
    tara-ocaml = self.callPackage ./tara-ocaml.nix { };
    tara-rocq = self.callPackage ./tara-rocq.nix { };
    tara-lean = self.callPackage ./tara-lean.nix { };
    tara-doc = self.callPackage ./tara-doc.nix { };
  });
  app = package: name: {
    type = "app";
    program = "${package}/bin/${name}";
    meta.description = package.meta.description;
  };
in
{
  packages = {
    asciidoctor-sail = scope.asciidoctorSail;
    sail-doc-tables = scope.sailDocTables;
    inherit (scope)
      sail
      rocq-sail-stdpp
      taracpu
      tara-tools
      tara-c
      tara-verilator
      tara-ocaml
      tara-rocq
      tara-lean
      tara-doc
      ;
    default = scope.tara-c;
  };
  checks = {
    sail-doc-tables = scope.sailDocTables;
    inherit (scope)
      tara-c
      tara-verilator
      tara-ocaml
      tara-rocq
      tara-lean
      tara-doc
      ;
  }
  # callPackage adds override functions to the attribute set; keep the checks.
  // lib.filterAttrs (_: lib.isDerivation) (scope.callPackage ./checks.nix { });
  apps = {
    tara-asm = app scope.tara-tools "tara-asm";
    tara-c = app scope.tara-c "tara-c";
    tara-verilator = app scope.tara-verilator "tara-verilator";
    tara-ocaml = app scope.tara-ocaml "tara-ocaml";
  };
  devShell = scope.callPackage ./shell.nix { };
}
