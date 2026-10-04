# Rocq definitions generated from the model's core (no strings).
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

# Compile the smoke test against the generated definitions.
[default]
build: definitions
    rocq compile -R "{{ build }}/rocq" Tara -o "{{ build }}/rocq/Smoke.vo" rocq/Smoke.v
