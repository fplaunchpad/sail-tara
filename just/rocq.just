# Generate Rocq definitions from the model's core (no strings).
[group('rocq')]
rocq-gen: (build-dir "rocq")
    sail --rocq --rocq-lib-style stdpp --rocq-output-dir "{{ build }}/rocq" -o Tara model/tara.sail

# Compile the generated Rocq types.
[group('rocq')]
rocq-types: rocq-gen
    rocq compile -R "{{ build }}/rocq" Tara "{{ build }}/rocq/Tara_types.v"

# Compile the generated Rocq definitions.
[group('rocq')]
rocq-defs: rocq-types
    rocq compile -R "{{ build }}/rocq" Tara "{{ build }}/rocq/Tara.v"

# Copy the smoke test next to the generated definitions.
[group('rocq')]
rocq-smoke-src: rocq-gen
    cp rocq/Smoke.v "{{ build }}/rocq/Smoke.v"

# Compile the smoke test against the generated definitions.
[group('rocq')]
rocq-smoke: rocq-defs rocq-smoke-src
    rocq compile -R "{{ build }}/rocq" Tara "{{ build }}/rocq/Smoke.v"

# Generate and check the Rocq definitions.
[group('rocq')]
rocq: rocq-smoke
