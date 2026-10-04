# Lem definitions generated from the model's core (no strings), typechecked, with a smoke test.
import "settings.just"

set working-directory := ".."

# Sail's Lem library, which the generated Lem imports.
library := sail_dir / "src/gen_lib"

# Sail also writes an Isabelle theory of lemmas, into the working directory unless told otherwise.

# Generate the Lem definitions.
[private]
generate: (build-dir "lem")
    sail --lem --lem-output-dir "{{ build }}/lem" --isa-output-dir "{{ build }}/lem" \
        -o tara model/tara.sail

# Lem notes each library module it imports, which is not a defect; every other warning is an
# error. -wl sets them all, so it comes first.

# Generate the Lem and typecheck it against Sail's library and Lem's own.
[default]
build: generate
    lem -wl err -wl_auto_import ign -lib "{{ library }}" \
        "{{ build }}/lem/tara_types.lem" "{{ build }}/lem/tara.lem"

# Lem extracts only the modules it is given, so name the library modules the generated Lem imports,
# and those they import. In the library's code, Lem reports that it renames identifiers (address,
# while), compiles patterns and that a nat may exceed OCaml's int: none of it matters here.

# Extract OCaml from the generated Lem and the Sail library modules it imports.
[private]
extract: generate (build-dir "lem/ocaml")
    lem -ocaml -wl_comp_message ign -wl_pat_comp ign -wl_rename ign \
        -outdir "{{ build }}/lem/ocaml" \
        "{{ library }}"/sail2_{values,string,operators,operators_bitlists,instr_kinds}.lem \
        "{{ library }}"/sail2_{prompt_monad,prompt,undefined}.lem \
        "{{ build }}/lem/tara_types.lem" "{{ build }}/lem/tara.lem"

# Lay the smoke test's dune project over the extracted OCaml.
[private]
project: extract
    cp -r lem/. "{{ build }}/lem/ocaml/"

# Compile the extracted model and the smoke test with dune.
[private]
compile: project
    dune build --root "{{ build }}/lem/ocaml"

# Run the manual's Fibonacci program on the model extracted to OCaml.
smoke: compile
    "{{ build }}/lem/ocaml/_build/default/smoke.exe"

# Format the smoke test's OCaml in place.
format:
    ocamlformat --inplace lem/smoke.ml

# Check that the smoke test's OCaml is formatted.
lint:
    ocamlformat --check lem/smoke.ml
