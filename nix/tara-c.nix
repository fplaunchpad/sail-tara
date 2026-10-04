# The C emulator, built with CMake from the model's C output.
{
  justDerivation,
  sail,
  cmake,
  ninja,
  gmp,
  zlib,
}:

justDerivation {
  pname = "tara-c";
  fileset = [
    ../model
    ../emulator/host.sail
    ../emulator/c
  ];
  nativeBuildInputs = [
    sail
    cmake
    ninja
  ];
  # just runs CMake itself (just c build), in build/c.
  dontUseCmakeConfigure = true;
  dontUseNinjaBuild = true;
  dontUseNinjaInstall = true;
  dontUseNinjaCheck = true;
  buildInputs = [
    gmp
    zlib
  ];
  recipes = [ "c::build" ];
  installPhase = ''
    install -Dm755 build/c/tara-c "$out/bin/tara-c"
  '';
  meta = {
    description = "TARA emulator built from the Sail model's C output";
    mainProgram = "tara-c";
  };
}
