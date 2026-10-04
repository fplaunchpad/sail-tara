# Generate the Lean project from the model's core (no strings).
[group('lean')]
lean-gen: (build-dir "lean")
    sail --lean --lean-single-file --lean-force-output --lean-output-dir "{{ build }}/lean" -o Tara model/tara.sail

# Copy the pinned lean-sail library ($LEAN_SAIL) where the project expects it.
[group('lean')]
lean-sail: (build-dir "lean")
    cp -rT --no-preserve=mode "$LEAN_SAIL" "{{ build }}/lean/lean-sail"

# Use the lakefile that builds against the local lean-sail.
[group('lean')]
lean-project: lean-gen lean-sail
    cp lean/lakefile.toml "{{ build }}/lean/Tara/lakefile.toml"

# Resolve the local lean-sail dependency (no network).
[group('lean')]
lean-update: lean-project
    cd "{{ build }}/lean/Tara" && lake update

# Build the generated Lean model.
[group('lean')]
lean-build: lean-update
    cd "{{ build }}/lean/Tara" && lake build

# Generate and build the Lean model.
[group('lean')]
lean: lean-build
