# Generate C for the emulator from the model and its host interface.
[group('c')]
c-gen: (build-dir "c")
    sail -c -O --c-no-main emulator/host.sail -o "{{ build }}/c/tara"

# Compile the emulator's own sources, with warnings as errors.
[group('c')]
c-objects: c-gen
    cd "{{ build }}/c" && cc -O2 -Wall -Wextra -Werror -I"{{ sail_dir }}/lib" -I. -c "{{ justfile_directory() }}"/emulator/c/*.c

# Link the C emulator against the generated model and the Sail C runtime.
[group('c')]
c-build: c-objects
    cc -O2 -I"{{ sail_dir }}/lib" -o "{{ build }}/c/tara-c" "{{ build }}"/c/*.o "{{ build }}/c/tara.c" "{{ sail_dir }}"/lib/*.c -lgmp -lz

# Build the C emulator, build/c/tara-c.
[group('c')]
c: c-build

# Check the C emulator against the golden Fibonacci dump and trace.
[group('c')]
golden-c: c (golden build / "c" / "tara-c")

# Format the C emulator's sources in place.
[group('c')]
c-format:
    clang-format -i emulator/c/*.c emulator/c/*.h

# Check that the C emulator's sources are formatted.
[group('c')]
c-format-check:
    clang-format --dry-run --Werror emulator/c/*.c emulator/c/*.h
