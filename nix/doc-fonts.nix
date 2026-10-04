{
  stdenvNoCC,
  fontforge,
  newcomputermodern,
  jetbrains-mono,
}:

stdenvNoCC.mkDerivation {
  pname = "tara-doc-fonts";
  inherit (newcomputermodern) src version;

  nativeBuildInputs = [ fontforge ];
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    mkdir -p fonts
    for font in \
      NewCM10-Regular \
      NewCM10-Italic \
      NewCM10-Bold \
      NewCM10-BoldItalic
    do
      fontforge -lang=ff -c 'Open($1); Generate($2);' "sfd/$font.sfd" "fonts/$font.ttf"
    done
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
    install -m 444 License.txt "$out/fonts/License.txt"
    install -m 444 "${jetbrains-mono.src}/OFL.txt" "$out/fonts/JetBrainsMono-OFL.txt"
    runHook postInstall
  '';

  meta = newcomputermodern.meta // {
    description = "New Computer Modern TTF fonts for the TARA documentation";
  };
}
