# Per-system outputs for the TARA toolchain.
{ pkgs }:

let
  inherit (pkgs) lib;
  # pyproject.toml pins the Python runtime dependencies to the releases nixpkgs
  # provides, so uv type-checks against the code that runs.
  pyproject = lib.importTOML ../pyproject.toml;
  runtimePackage =
    ps: requirement:
    let
      pin = builtins.match "([A-Za-z0-9_.-]+)==(.+)" requirement;
      package = ps.${lib.elemAt pin 0};
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
      ps: map (runtimePackage ps) pyproject.project.dependencies
    );

    sail = self.callPackage ./sail.nix { };
    rocq-sail-stdpp = self.rocqPackages.callPackage ./rocq-sail-stdpp.nix { };
    taracpu = self.callPackage ./taracpu.nix { };
    tara-tools = self.callPackage ./tara-tools.nix { };
  });
in
{
  packages = {
    inherit (scope)
      sail
      rocq-sail-stdpp
      taracpu
      tara-tools
      ;
  };
  checks = { };
  apps = {
    tara-asm = {
      type = "app";
      program = "${scope.tara-tools}/bin/tara-asm";
    };
  };
  devShell = scope.callPackage ./shell.nix { };
}
