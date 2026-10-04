let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/c9fe7d12cd78d1adcd12dd15e24432dde5b155a0.tar.gz";
    sha256 = "sha256-5AIVFLRcx8YAwbFTVPTs7YhwJH7JyHfAQsvXmpovcXI=";
  };
  pkgs = import nixpkgs { };
  ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_5;
  sailAttrs = {
    version = "0.20.3";
    src = pkgs.fetchurl {
      url = "https://github.com/rems-project/sail/releases/download/0.20.3/sail-0.20.3.tbz";
      hash = "sha256-CyI+2D9SGth+qs2IGGOQ+68LlE9jxqBKPr35ah/1pgw=";
    };
    postInstall = ''
      wrapProgram $out/bin/sail \
        --set SAIL_DIR $out/share/sail \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.z3 ]}
    '';
  };
  sailUnpatched = ocamlPackages.sail.overrideAttrs (_: sailAttrs // { patches = [ ]; });
  sailPatched = ocamlPackages.sail.overrideAttrs (
    _:
    sailAttrs
    // {
      patches = [ (pkgs.writeText "fix.patch" (builtins.readFile ./fix.patch)) ];
    }
  );
in
pkgs.runCommand "sail-lem-register-keywords-reproduction"
  {
    nativeBuildInputs = [ ocamlPackages.lem ];
  }
  ''
    set -eu
    mkdir -p "$TMPDIR/unpatched" "$TMPDIR/patched"

    ${sailUnpatched}/bin/sail --lem \
      --lem-output-dir "$TMPDIR/unpatched" --isa-output-dir "$TMPDIR/unpatched" \
      -o repro ${./model.sail}
    grep -F "read_from = (fun s -> s.MEM)" "$TMPDIR/unpatched/repro_types.lem"
    grep -F "s with MEM = v" "$TMPDIR/unpatched/repro_types.lem"
    if ${ocamlPackages.lem}/bin/lem -wl err -wl_auto_import ign \
      -lib "${sailUnpatched}/share/sail/src/gen_lib" \
      "$TMPDIR/unpatched/repro_types.lem" "$TMPDIR/unpatched/repro.lem" \
      >"$TMPDIR/unpatched/lem.log" 2>&1; then
      echo "expected unpatched Sail Lem output to fail Lem parsing" >&2
      exit 1
    fi
    cat "$TMPDIR/unpatched/lem.log"
    grep -F "Syntax error" "$TMPDIR/unpatched/lem.log"

    ${sailPatched}/bin/sail --lem \
      --lem-output-dir "$TMPDIR/patched" --isa-output-dir "$TMPDIR/patched" \
      -o repro ${./model.sail}
    grep -F "read_from = (fun s -> s.MEM')" "$TMPDIR/patched/repro_types.lem"
    grep -F "s with MEM' = v" "$TMPDIR/patched/repro_types.lem"
    ${ocamlPackages.lem}/bin/lem -wl err -wl_auto_import ign \
      -lib "${sailPatched}/share/sail/src/gen_lib" \
      "$TMPDIR/patched/repro_types.lem" "$TMPDIR/patched/repro.lem" \
      >"$TMPDIR/patched/lem.log" 2>&1 || {
        cat "$TMPDIR/patched/lem.log" >&2
        exit 1
      }

    mkdir -p "$out/before" "$out/after"
    cp "$TMPDIR/unpatched/repro_types.lem" "$TMPDIR/unpatched/repro.lem" "$out/before/"
    cp "$TMPDIR/unpatched/lem.log" "$out/before/lem.log"
    cp "$TMPDIR/patched/repro_types.lem" "$TMPDIR/patched/repro.lem" "$out/after/"
    cp "$TMPDIR/patched/lem.log" "$out/after/lem.log"
    echo "unpatched generation fails Lem parsing; patched generation typechecks" > "$out/result"
  ''
