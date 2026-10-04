# Lean definitions generated from the model's core (no strings), and an executable smoke test.
import "settings.just"

set working-directory := ".."

# Generate the Lean project NAME from a Sail program: an executable if it defines main.
[private]
generate name source: (build-dir "lean")
    sail --lean --lean-single-file --lean-force-output --lean-executable \
        --lean-lib-path ../lean-sail --lean-output-dir "{{ build }}/lean" -o "$1" "$2"

# Copy the pinned lean-sail library ($LEAN_SAIL) where the projects' lakefiles expect it.
[private]
library: (build-dir "lean")
    cp -rT --no-preserve=mode "$LEAN_SAIL" "{{ build }}/lean/lean-sail"

# Resolve the local lean-sail dependency of the project NAME (no network).
[private]
update name source: (generate name source) library
    cd "{{ build }}/lean/$1" && lake update

# Build the generated Lean model.
[default]
build: (update "Tara" "model/tara.sail")
    cd "{{ build }}/lean/Tara" && lake build

# Build and run the smoke test: the manual's Fibonacci program on the generated Lean model.
smoke: (update "Smoke" "lean/smoke.sail")
    cd "{{ build }}/lean/Smoke" && lake exe run
