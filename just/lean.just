# Lean definitions generated from the model's core (no strings).
import "settings.just"

set working-directory := ".."

# Generate the Lean project.
[private]
generate: (build-dir "lean")
    sail --lean --lean-single-file --lean-force-output --lean-output-dir "{{ build }}/lean" -o Tara model/tara.sail

# Copy the pinned lean-sail library ($LEAN_SAIL) where the project expects it.
[private]
library: (build-dir "lean")
    cp -rT --no-preserve=mode "$LEAN_SAIL" "{{ build }}/lean/lean-sail"

# Use the lakefile that builds against the local lean-sail.
[private]
project: generate library
    cp lean/lakefile.toml "{{ build }}/lean/Tara/lakefile.toml"

# Resolve the local lean-sail dependency (no network).
[private]
update: project
    cd "{{ build }}/lean/Tara" && lake update

# Build the generated Lean model.
[default]
build: update
    cd "{{ build }}/lean/Tara" && lake build
