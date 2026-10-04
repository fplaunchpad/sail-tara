# The C emulator, built from the model's C output.
import "settings.just"

set working-directory := ".."

# Generate C from the model and its host interface.
[private]
generate: (build-dir "c")
    sail -c -O --c-no-main emulator/host.sail -o "{{ build }}/c/tara"

# Compile the emulator's own sources as C11 with POSIX.1-2008, with warnings as errors.
[private]
compile: generate
    cd "{{ build }}/c" && cc -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -Wall -Wextra -Werror -I"{{ sail_dir }}/lib" -I. -c "{{ justfile_directory() }}"/emulator/c/*.c

# Link the C emulator, build/c/tara-c.
[default]
build: compile
    cc -O2 -I"{{ sail_dir }}/lib" -o "{{ build }}/c/tara-c" "{{ build }}"/c/*.o "{{ build }}/c/tara.c" "{{ sail_dir }}"/lib/*.c -lgmp -lz

# Assemble a TARA program and run it: just c run PROGRAM.tara [OPTION...]
run program *options: build (assemble program)
    "{{ build }}/c/tara-c" "${@:2}" "{{ build }}/programs/$(basename "$1" .tara).bin"

# Format the C sources in place.
format:
    clang-format -i emulator/c/*.c emulator/c/*.h

# Check that the C sources are formatted.
lint:
    clang-format --dry-run --Werror emulator/c/*.c emulator/c/*.h
