# The OCaml emulator, built from the model's OCaml output.
import "settings.just"

set working-directory := ".."

# Remove the previous overlay, so deleted sources do not linger.
[private]
clean: (build-dir "ocaml")
    rm -rf "{{ build }}/ocaml/src"

# Generate OCaml from the model and its host interface.
[private]
generate: clean
    sail --ocaml --ocaml-nobuild --ocaml-build-dir "{{ build }}/ocaml" -o tara emulator/host.sail

# Lay the emulator's dune project over the generated one.
[private]
project: generate
    cp -r emulator/ocaml/. "{{ build }}/ocaml/"

# Compile the emulator with dune.
[private]
compile: project
    dune build --root "{{ build }}/ocaml"

# Link the OCaml emulator to build/ocaml/tara-ocaml.
[default]
build: compile
    ln -sf _build/default/src/main.exe "{{ build }}/ocaml/tara-ocaml"

# Assemble a TARA program and run it to its end: just ocaml run PROGRAM.tara [OPTION...]
run program *options: build (assemble program)
    "{{ build }}/ocaml/tara-ocaml" run "${@:2}" "{{ build }}/programs/$(basename "$1" .tara).bin"

# Assemble a TARA program and play it in the terminal: just ocaml play PROGRAM.tara [OPTION...]
play program *options: build (assemble program)
    "{{ build }}/ocaml/tara-ocaml" play "${@:2}" "{{ build }}/programs/$(basename "$1" .tara).bin"

# Format the OCaml sources in place.
format:
    ocamlformat --inplace emulator/ocaml/src/*.ml emulator/ocaml/src/*.mli

# Check that the OCaml sources are formatted.
lint:
    ocamlformat --check emulator/ocaml/src/*.ml emulator/ocaml/src/*.mli
