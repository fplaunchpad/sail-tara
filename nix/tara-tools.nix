# Hand-written, stdlib-only Python commands built on the TARA Studio modules.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  python,
  taracpu,
}:

let
  commands = [ "asm" ];
in
stdenvNoCC.mkDerivation {
  pname = "tara-tools";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../tools;
    fileset = ../tools/tara;
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/tara-tools" "$out/bin"
    cp -r tara "$out/lib/tara-tools/"
    for command in ${lib.escapeShellArgs commands}; do
      makeWrapper ${lib.getExe python} "$out/bin/tara-$command" \
        --add-flags "-m tara.$command" \
        --prefix PYTHONPATH : "$out/lib/tara-tools:${taracpu}/share/taracpu"
    done
    runHook postInstall
  '';

  meta.description = "tara-asm and related wrappers around the TARA Studio reference tools";
}
