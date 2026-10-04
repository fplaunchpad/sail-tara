# The Sail model: typecheck, unit tests and formatting.
import "settings.just"

set working-directory := ".."

# Sail sources, formatted and checked together.
sources := "model/*.sail emulator/*.sail tests/model/*.sail"
# Formatter settings; line_width is also the limit for every Sail line.
config := "sail_config.json"
width := shell('jq .fmt.line_width "$1"', config)

# Typecheck a Sail file and everything it includes.
[private]
typecheck file:
    sail --just-check "$1"

# Typecheck the model, the emulators' host interface and the unit tests.
[default]
check: (typecheck "emulator/host.sail") (typecheck "tests/model/test_tara.sail")

# Generate C for the unit tests.
[private]
generate: (build-dir "model")
    sail -c -O tests/model/test_tara.sail -o "{{ build }}/model/tests"

# Compile the unit tests against the Sail C runtime.
[private]
compile: generate
    cc -O2 -I"{{ sail_dir }}/lib" -o "{{ build }}/model/tests" "{{ build }}/model/tests.c" "{{ sail_dir }}"/lib/*.c -lgmp -lz

# Run the unit tests.
test: compile
    "{{ build }}/model/tests"

# Format the Sail sources in place.
format:
    sail --sail-config {{ config }} --fmt {{ sources }}

# Check that the Sail sources are formatted.
[private]
format-check:
    status=0; for file in {{ sources }}; do sail --sail-config {{ config }} --fmt --fmt-emit stdout "$file" | diff -u --label "$file" --label "$file (formatted)" "$file" - || status=1; done; exit "$status"

# Check that no Sail line is longer than the formatter's line width.
[private]
width-check:
    LC_ALL=C awk -v width={{ width }} 'length > width { print FILENAME ":" FNR ": " length " columns"; status = 1 } END { exit status }' {{ sources }}

# Check the formatting and line width of the Sail sources.
lint: format-check width-check
