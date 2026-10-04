# Remove the previous overlay, so deleted sources do not linger.
[group('ocaml')]
ocaml-clean: (build-dir "ocaml")
    rm -rf "{{ build }}/ocaml/src"

# Generate OCaml for the emulator from the model and its host interface.
[group('ocaml')]
ocaml-gen: ocaml-clean
    sail --ocaml --ocaml-nobuild --ocaml-build-dir "{{ build }}/ocaml" -o tara emulator/host.sail

# Lay the emulator's dune project over the generated one.
[group('ocaml')]
ocaml-project: ocaml-gen
    cp -r emulator/ocaml/. "{{ build }}/ocaml/"

# Build the OCaml emulator with dune.
[group('ocaml')]
ocaml-build: ocaml-project
    dune build --root "{{ build }}/ocaml"

# Link the OCaml emulator to build/ocaml/tara-ocaml.
[group('ocaml')]
ocaml-link: ocaml-build
    ln -sf _build/default/src/main.exe "{{ build }}/ocaml/tara-ocaml"

# Build the OCaml emulator, build/ocaml/tara-ocaml.
[group('ocaml')]
ocaml: ocaml-link

# Check the OCaml emulator against the golden Fibonacci dump and trace.
[group('ocaml')]
golden-ocaml: ocaml (golden build / "ocaml" / "tara-ocaml")

# Check the OCaml emulator against the shared command-line contract.
[group('ocaml')]
cli-ocaml: ocaml (cli build / "ocaml" / "tara-ocaml")

# Format the OCaml emulator's sources in place.
[group('ocaml')]
ocaml-format:
    ocamlformat --inplace emulator/ocaml/src/*.ml emulator/ocaml/src/*.mli

# Check that the OCaml emulator's sources are formatted.
[group('ocaml')]
ocaml-format-check:
    ocamlformat --check emulator/ocaml/src/*.ml emulator/ocaml/src/*.mli
