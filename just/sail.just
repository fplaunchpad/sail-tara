# Typecheck the model.
[group('model')]
check-model:
    sail --just-check model/tara.sail

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
