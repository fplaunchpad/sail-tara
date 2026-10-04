# TARA: Sail ISA specification and the toolchain generated from it.
# Run inside `nix develop` (or direnv). Outputs go to $TARA_BUILD (default build/).

import "just/settings.just"
import "just/sail.just"
import "just/c.just"
import "just/ocaml.just"
import "just/rocq.just"
import "just/lean.just"
import "just/doc.just"
import "just/golden.just"

# Python development tools: lint, format, typecheck.
[group('maintenance')]
mod python "just/python.just"

build := env("TARA_BUILD", justfile_directory() / "build")
sail_dir := `sail --dir`

# Create a directory under the build root.
[private]
build-dir dir:
    mkdir -p "{{ build }}/$1"

default:
    @just --list

# Format the Sail, C and OCaml sources (Python: just python format).
[group('maintenance')]
format: sail-format c-format ocaml-format

# Check the formatting of the Sail, C and OCaml sources (Python: just python lint).
[group('maintenance')]
lint: sail-lint c-format-check ocaml-format-check

# Remove build outputs.
[group('maintenance')]
clean:
    rm -rf "{{ build }}"

# Run every flake check (hermetic builds, tests, difftests).
[group('maintenance')]
ci:
    nix flake check -L
