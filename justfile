# TARA: Sail ISA specification and the toolchain generated from it.
# Run inside `nix develop` (or direnv). Outputs go to $TARA_BUILD (default build/).

import "just/settings.just"

# The Sail model: typecheck and formatting.
mod model "just/model.just"

# The C emulator.
mod c "just/c.just"

# The OCaml emulator.
mod ocaml "just/ocaml.just"

# Rocq definitions generated from the model, with proofs of their properties.
mod rocq "just/rocq.just"

# Lean definitions generated from the model, with proofs of their properties.
mod lean "just/lean.just"

# The specification typeset from the model.
mod doc "just/doc.just"

# Instruction table metadata from Sail's typed AST.
mod sail-doc "just/sail-doc.just"

# Python tooling: dependencies, lint, format, typecheck.
mod python "just/python.just"

# List the recipes and modules.
[default]
list:
    @just --list

# Build the emulators, Rocq and Lean definitions, and the PDF and HTML specification.
build: c::build ocaml::build rocq::build lean::build doc::build doc::html

# Test the emulators against the reference model; ARGS go to pytest (e.g. -k tara-c).
test *args: c::build ocaml::build
    "$TARA_PYTHON" -m pytest --emulator="{{ build }}/c/tara-c" \
        --emulator="{{ build }}/ocaml/tara-ocaml" "$@"

# Format Sail, C, OCaml, Python and documentation sources.
format: model::format c::format ocaml::format sail-doc::format python::format doc::format

# Check the formatting of every source, Python lint and types.
lint: model::lint c::lint ocaml::lint sail-doc::lint rocq::lint lean::lint doc::lint python::lint

# Remove build outputs.
clean:
    rm -rf "{{ build }}"

# Run every flake check.
ci:
    nix flake check --no-update-lock-file -L
