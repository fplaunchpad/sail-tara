# Lean definitions generated from the model's core (no strings), and proofs about them.
import "settings.just"

set working-directory := ".."

# Formatter settings; line_width is also the limit for every Lean line.
config := "sail_config.json"
width := shell('jq .fmt.line_width "$1"', config)

# Generate the Lean project.
[private]
generate: (build-dir "lean")
    sail --lean --lean-single-file --lean-force-output --lean-output-dir "{{ build }}/lean" \
        -o Tara model/tara.sail

# Copy the pinned lean-sail library ($LEAN_SAIL) where the project expects it.
[private]
library: (build-dir "lean")
    cp -rT --no-preserve=mode "$LEAN_SAIL" "{{ build }}/lean/lean-sail"

# Lay lean/ over the generated project: its lakefile and the proofs.
[private]
project: generate library
    cp -rT lean "{{ build }}/lean/Tara"

# Resolve the local lean-sail dependency (no network).
[private]
update: project
    lake --dir "{{ build }}/lean/Tara" update

# Build the generated Lean model and check the proofs about it.
[default]
build: update
    lake --dir "{{ build }}/lean/Tara" build

# Check that no Lean source line is longer than the formatter's line width.
lint:
    LC_ALL=C.UTF-8 awk -v width={{ width }} \
        'length > width { print FILENAME ":" FNR ": " length " columns"; status = 1 } \
        END { exit status }' lean/Tara/*.lean
