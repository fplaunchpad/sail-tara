{
  description = "TARA ISA: Sail specification, C and OCaml emulators, Rocq/Lean extractions, LaTeX reference";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    lean4-nix = {
      url = "github:lenianiva/lean4-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      lean4-nix,
    }:
    let
      inherit (nixpkgs) lib;
      # x86_64-linux is tested; the other systems are best-effort.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSystem =
        f:
        lib.genAttrs systems (
          system:
          f (
            import ./nix {
              pkgs = import nixpkgs {
                inherit system;
                overlays = [ (lean4-nix.readToolchainFile ./lean/lean-toolchain) ];
              };
            }
          )
        );
    in
    {
      packages = forEachSystem (tara: tara.packages);
      checks = forEachSystem (tara: tara.checks);
      apps = forEachSystem (tara: tara.apps);
      devShells = forEachSystem (tara: {
        default = tara.devShell;
      });
      formatter = lib.genAttrs systems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
