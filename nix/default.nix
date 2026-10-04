# Per-system outputs for the TARA toolchain.
{ pkgs }:

let
  inherit (pkgs) lib;
  scope = lib.makeScope pkgs.newScope (self: {
    ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_5;
    rocqPackages = pkgs.rocqPackages_9_3;
    python = pkgs.python315;

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
