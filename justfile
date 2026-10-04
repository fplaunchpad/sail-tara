# TARA: Sail ISA specification and the toolchain generated from it.
# Run inside `nix develop` (or direnv). Outputs go to $TARA_BUILD (default build/).

import "just/settings.just"

# The Sail model: typecheck, unit tests, formatting.
mod model "just/model.just"

# The C emulator.
mod c "just/c.just"

# The OCaml emulator.
mod ocaml "just/ocaml.just"

# Rocq definitions generated from the model.
mod rocq "just/rocq.just"

# Lean definitions generated from the model.
mod lean "just/lean.just"

# Lem definitions generated from the model.
mod lem "just/lem.just"

# The specification typeset from the model.
mod doc "just/doc.just"

# Python tooling: dependencies, lint, format, typecheck.
mod python "just/python.just"

# List the recipes and modules.
[default]
list:
    @just --list

# Build the emulators, the Rocq, Lean and Lem definitions and the PDF.
build: c::build ocaml::build rocq::build lean::build lem::build doc::build doc::html

# Test the emulators against the reference model; ARGS go to pytest (e.g. -k tara-c).
test *args: c::build ocaml::build
    "$TARA_PYTHON" -m pytest --emulator="{{ build }}/c/tara-c" --emulator="{{ build }}/ocaml/tara-ocaml" "$@"

# Format the Sail, C, OCaml and Python sources.
format: model::format c::format ocaml::format lem::format python::format

# Check the formatting of every source, Python lint and types.
lint: model::lint c::lint ocaml::lint lem::lint python::lint (python::format "--check") python::typecheck

# Remove build outputs.
clean:
    rm -rf "{{ build }}"

# Run every flake check.
ci:
    nix flake check -L
