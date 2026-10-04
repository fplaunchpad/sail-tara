# The native Sail documentation-table backend.
import "settings.just"

set working-directory := ".."

plugin := build / "sail-doc/sail_doc_tables.cmxs"
plugin-library := build / "sail-doc/_build/default/src/tara_doc_tables.cmxa"
link-packages := "core,libsail,ppx_yojson_conv_lib,ppx_string.runtime"

# Compile the Sail metadata extractor as a reusable native library.
[private]
compile: (build-dir "sail-doc")
    dune build --root tools/sail-doc --build-dir "{{ build }}/sail-doc/_build" src/tara_doc_tables.cmxa

# Link a Findlib-aware native plugin, resolving Core's complete runtime closure.
[default]
build: compile
    ocamlfind ocamlopt -shared -linkall -linkpkg -package "{{ link-packages }}" -dontlink libsail -dontlink yojson -o "{{ plugin }}" "{{ plugin-library }}"

# Format the handwritten plugin sources.
format:
    ocamlformat --inplace tools/sail-doc/src/*.ml tools/sail-doc/src/*.mli

# Check the handwritten plugin sources are formatted.
lint:
    ocamlformat --check tools/sail-doc/src/*.ml tools/sail-doc/src/*.mli
