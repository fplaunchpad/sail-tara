# The TARA Studio wheel (GPL-3.0-or-later), unpacked for its assembler, its
# reference simulator and its bundled example programs. Fetched, never vendored.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "taracpu";
  version = "1.2.2";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/5f/fd/d2a7933d31e42f3c79c48bade7dc608137a8988f75748ad4b85ff0277ebd/taracpu-${finalAttrs.version}-py3-none-any.whl";
    hash = "sha256-8Y8sm+pFqxBpIGBNbMxr5yTJ+YaFWBNE5ObfE8mV9UQ=";
  };

  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    runHook preUnpack
    unzip -q "$src" -d wheel
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/taracpu"
    cp -r wheel/src "$out/share/taracpu/"
    cp wheel/taracpu-${finalAttrs.version}.dist-info/licenses/LICENSE "$out/share/taracpu/"
    runHook postInstall
  '';

  meta = {
    description = "TARA Studio assembler, simulator and example programs (wheel contents)";
    homepage = "https://pypi.org/project/taracpu/";
    license = lib.licenses.gpl3Plus;
  };
})
