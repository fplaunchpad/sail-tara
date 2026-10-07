# Sail 0.20.3 on the OCaml 5.5 package set. nixpkgs pins 0.20.1; its menhir
# compatibility patch is already upstream in 0.20.3.
{
  lib,
  fetchurl,
  ocamlPackages,
  z3,
}:

ocamlPackages.sail.overrideAttrs (_: rec {
  version = "0.20.3";
  src = fetchurl {
    url = "https://github.com/rems-project/sail/releases/download/${version}/sail-${version}.tbz";
    hash = "sha256-CyI+2D9SGth+qs2IGGOQ+68LlE9jxqBKPr35ah/1pgw=";
  };
  # Keep decoder reachability shared in the SystemVerilog backend; see emulator/verilator/README.md.
  patches = [ ./patches/sail-sv-reachability.patch ];
  # The typechecker shells out to z3; the upstream wrapper only sets SAIL_DIR.
  postInstall = ''
    wrapProgram $out/bin/sail \
      --set SAIL_DIR $out/share/sail \
      --prefix PATH : ${lib.makeBinPath [ z3 ]}
  '';
})
