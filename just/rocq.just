# Rocq definitions generated from the model's core (no strings), with a smoke test and a proof.
import "settings.just"

set working-directory := ".."

# Generate the Rocq definitions.
[private]
generate: (build-dir "rocq")
    sail --rocq --rocq-lib-style stdpp --rocq-output-dir "{{ build }}/rocq" -o Tara model/tara.sail

# Compile the generated types.
[private]
types: generate
    rocq compile -R "{{ build }}/rocq" Tara "{{ build }}/rocq/Tara_types.v"

# Compile the generated definitions.
[private]
definitions: types
    rocq compile -R "{{ build }}/rocq" Tara "{{ build }}/rocq/Tara.v"

# Compile rocq/NAME.v against the generated definitions and the other sources, as Tara.NAME.
[private]
compile name: definitions
    rocq compile -R "{{ build }}/rocq" Tara -R rocq Tara -o "{{ build }}/rocq/$1.vo" "rocq/$1.v"

# Run the generated model on the hardware manual's Fibonacci program and a few instructions.
smoke: (compile "Run") (compile "Smoke")

# Prove that decoding an encoded instruction gives the instruction back.
codec: (compile "Codec")

# Compile the generated definitions, then the smoke test and the codec proof.
[default]
build: smoke codec
