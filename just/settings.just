# Shared execution policy and paths for the root justfile and its modules.
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set positional-arguments
set lazy

# Build outputs; justfile_directory() is the repository root, also inside a module.
build := env("TARA_BUILD", justfile_directory() / "build")
sail_dir := `sail --dir`

# Create a directory under the build root.
[private]
build-dir dir:
    mkdir -p "{{ build }}/$1"

# Assemble a TARA program into build/programs/NAME.bin.
[private]
assemble program: (build-dir "programs")
    tara-asm "$1" -o "{{ build }}/programs/$(basename "$1" .tara).bin"
