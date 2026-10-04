# Sail sources, formatted and checked together.
sail_sources := "model/*.sail emulator/*.sail tests/*.sail"
# Formatter settings; line_width is also the limit for every Sail line.
sail_config := "sail_config.json"
sail_width := shell('jq .fmt.line_width "$1"', sail_config)

# Typecheck the model.
[group('model')]
check-model:
    sail --just-check model/syntax.sail

# Typecheck the Sail test suite.
[group('model')]
check-tests:
    sail --just-check tests/test_tara.sail

# Typecheck the model and its Sail test suite.
[group('model')]
check: check-model check-tests

# Generate C for the Sail test suite.
[group('model')]
test-c: check-tests (build-dir "test")
    sail -c -O tests/test_tara.sail -o "{{ build }}/test/tara_tests"

# Compile the generated test suite against the Sail C runtime.
[group('model')]
test-build: test-c
    cc -O2 -I"{{ sail_dir }}/lib" -o "{{ build }}/test/tara_tests" "{{ build }}/test/tara_tests.c" "{{ sail_dir }}"/lib/*.c -lgmp -lz

# Run the Sail test suite.
[group('model')]
test: test-build
    "{{ build }}/test/tara_tests"

# Format the Sail sources in place.
[group('model')]
sail-format:
    sail --sail-config {{ sail_config }} --fmt {{ sail_sources }}

# Check that the Sail sources are formatted.
[group('model')]
sail-format-check:
    status=0; for file in {{ sail_sources }}; do sail --sail-config {{ sail_config }} --fmt --fmt-emit stdout "$file" | diff -u --label "$file" --label "$file (formatted)" "$file" - || status=1; done; exit "$status"

# Check that no Sail line is longer than the formatter's line width.
[group('model')]
sail-width-check:
    LC_ALL=C awk -v width={{ sail_width }} 'length > width { print FILENAME ":" FNR ": " length " columns"; status = 1 } END { exit status }' {{ sail_sources }}

# Check the formatting and line width of the Sail sources.
[group('model')]
sail-lint: sail-format-check sail-width-check
