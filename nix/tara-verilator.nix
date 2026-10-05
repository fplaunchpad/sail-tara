# The C++ frontend with instruction execution through Sail-generated SystemVerilog.
{
  justDerivation,
  sail,
  verilator,
  cli11,
  tara-tools,
  cmake,
  ninja,
  gmp,
  zlib,
}:

justDerivation {
  pname = "tara-verilator";
  fileset = [
    ../model
    ../emulator/host.sail
    ../emulator/state.sail
    ../emulator/verilator
    ../tests/programs/state_transfer.tara
    ../tests/programs/illegal.tara
  ];
  nativeBuildInputs = [
    sail
    verilator
    tara-tools
    cmake
    ninja
  ];
  dontUseCmakeConfigure = true;
  dontUseNinjaBuild = true;
  dontUseNinjaInstall = true;
  dontUseNinjaCheck = true;
  buildInputs = [
    gmp
    zlib
    cli11
  ];
  recipes = [ "verilator::build" ];
  checkRecipes = [ "verilator::check" ];
  installPhase = ''
    install -Dm755 build/verilator/tara-verilator "$out/bin/tara-verilator"
    install -Dm644 build/verilator/tara.sv "$out/share/tara-verilator/tara.sv"
    install -Dm644 build/verilator/sail_modules.sv "$out/share/tara-verilator/sail_modules.sv"
  '';
  meta = {
    description = "TARA emulator executing Sail-generated SystemVerilog with Verilator";
    mainProgram = "tara-verilator";
  };
}
