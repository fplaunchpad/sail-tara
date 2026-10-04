{
  stdenvNoCC,
  lib,
  fetchurl,
  python3Packages,
  jetbrains-mono,
}:

let
  petronaRevision = "9710da1eacb3be272583c3224dcb70f9da6eadbb";
  petrona =
    name: hash:
    fetchurl {
      inherit hash;
      name = lib.strings.sanitizeDerivationName name;
      url = "https://raw.githubusercontent.com/google/fonts/${petronaRevision}/ofl/petrona/${
        lib.strings.replaceStrings [ "[" "]" ] [ "%5B" "%5D" ] name
      }";
    };
  petronaRegular = petrona "Petrona[wght].ttf" "sha256-Dt53+/cmVBz5Ps57chp7Bp8ATLQTqyBfdJY1YAFasHU=";
  petronaItalic = petrona "Petrona-Italic[wght].ttf" "sha256-9K1ZkJPSmmaOL5ReAntHuu6EdmR9kryMI6ibD4bAgHg=";
  petronaLicense = petrona "OFL.txt" "sha256-qIn/d7db6LzRRW/xR+udrGR/PrIX+tUPtId0lohPbcs=";
in
stdenvNoCC.mkDerivation {
  pname = "tara-doc-fonts";
  version = petronaRevision;
  dontUnpack = true;
  dontConfigure = true;

  nativeBuildInputs = [ python3Packages.fonttools ];

  buildPhase = ''
    runHook preBuild
    mkdir -p fonts
    fonttools varLib.instancer --update-name-table ${petronaRegular} wght=400 --output=fonts/Petrona-Regular.ttf
    fonttools varLib.instancer --update-name-table ${petronaRegular} wght=700 --output=fonts/Petrona-Bold.ttf
    fonttools varLib.instancer --update-name-table ${petronaItalic} wght=400 --output=fonts/Petrona-Italic.ttf
    fonttools varLib.instancer --update-name-table ${petronaItalic} wght=700 --output=fonts/Petrona-BoldItalic.ttf
    for style in Regular Italic Bold BoldItalic; do
      install -m 444 \
        "${jetbrains-mono}/share/fonts/truetype/JetBrainsMono-$style.ttf" \
        "fonts/JetBrainsMono-$style.ttf"
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/fonts"
    install -m 444 fonts/*.ttf "$out/fonts/"
    install -m 444 ${petronaLicense} "$out/fonts/Petrona-OFL.txt"
    install -m 444 "${jetbrains-mono.src}/OFL.txt" "$out/fonts/JetBrainsMono-OFL.txt"
    runHook postInstall
  '';

  meta = {
    description = "Petrona and JetBrains Mono fonts for the TARA documentation";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
