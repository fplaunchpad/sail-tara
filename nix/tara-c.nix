# The C emulator, checked against the golden Fibonacci run.
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
    ../tests/programs
    ../tests/golden
  ];
  nativeBuildInputs = [ sail ];
  buildInputs = [
    gmp
    zlib
  ];
  recipes = [ "c" ];
  checkRecipes = [ "golden-c" ];
  installPhase = ''
    install -Dm755 build/c/tara-c "$out/bin/tara-c"
  '';
  meta = {
    description = "TARA emulator built from the Sail model's C output";
    mainProgram = "tara-c";
  };
}
