# The C emulator, built from the model's C output.
{
  justDerivation,
  sail,
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
  nativeBuildInputs = [ sail ];
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
