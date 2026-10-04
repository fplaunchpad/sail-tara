# The C emulator, built with CMake from the model's C output.
import "settings.just"

set working-directory := ".."

# Configure the CMake build in build/c.
[private]
configure:
    cmake -S emulator/c -B "{{ build }}/c" -G Ninja -DCMAKE_BUILD_TYPE=Release

# Build the C emulator, build/c/tara-c.
[default]
build: configure
    cmake --build "{{ build }}/c"

# Assemble a TARA program and run it to its end: just c run PROGRAM.tara [OPTION...]
run program *options: build (assemble program)
    "{{ build }}/c/tara-c" run "${@:2}" "{{ build }}/programs/$(basename "$1" .tara).bin"

# Assemble a TARA program and play it in the terminal: just c play PROGRAM.tara [OPTION...]
play program *options: build (assemble program)
    "{{ build }}/c/tara-c" play "${@:2}" "{{ build }}/programs/$(basename "$1" .tara).bin"

# Format the C sources in place.
format:
    clang-format -i emulator/c/src/*.c emulator/c/src/*.h

# Check that the C sources are formatted.
[private]
format-check:
    clang-format --dry-run --Werror emulator/c/src/*.c emulator/c/src/*.h

# Check the C sources with clang-tidy (emulator/c/.clang-tidy), with the build's compile commands.
[private]
tidy: build
    clang-tidy --quiet -p "{{ build }}/c" emulator/c/src/*.c

# Check the formatting of the C sources, and clang-tidy's checks.
lint: format-check tidy
