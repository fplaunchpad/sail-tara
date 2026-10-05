# The Verilator emulator, executing Sail-generated SystemVerilog.
import "settings.just"

set working-directory := ".."

# Configure the C++ frontend and the generated step module.
[private]
configure:
    cmake -S emulator/verilator -B "{{ build }}/verilator" -G Ninja -DCMAKE_BUILD_TYPE=Release

# Generate SystemVerilog and its support include in build/verilator.
generate: configure
    cmake --build "{{ build }}/verilator" --target generate

# Build the Verilator emulator, build/verilator/tara-verilator.
[default]
build: configure
    cmake --build "{{ build }}/verilator"

# Assemble a TARA program and run it: just verilator run PROGRAM.tara [OPTION...]
run program *options: build (assemble program)
    "{{ build }}/verilator/tara-verilator" run "${@:2}" "{{ build }}/programs/$(basename "$1" .tara).bin"

# Assemble a TARA program and play it in the terminal.
play program *options: build (assemble program)
    "{{ build }}/verilator/tara-verilator" play "${@:2}" "{{ build }}/programs/$(basename "$1" .tara).bin"

# Check complete state transfer, halted preservation and illegal-opcode advancement.
check: build (assemble "tests/programs/state_transfer.tara") (assemble "tests/programs/illegal.tara")
    "{{ build }}/verilator/state-test" "{{ build }}/programs/state_transfer.bin" "{{ build }}/programs/illegal.bin"

# Format the authored C++ sources.
format:
    clang-format -i emulator/verilator/src/*.cc emulator/verilator/src/*.h emulator/verilator/tests/*.cc

# Check the formatting of the authored C++ sources.
[private]
format-check:
    clang-format --dry-run --Werror emulator/verilator/src/*.cc emulator/verilator/src/*.h emulator/verilator/tests/*.cc

# Check the authored adapter and state test with clang-tidy.
[private]
tidy: build
    clang-tidy --quiet -p "{{ build }}/verilator" emulator/verilator/src/*.cc emulator/verilator/tests/*.cc

# Check C++ formatting and clang-tidy's checks.
lint: format-check tidy
