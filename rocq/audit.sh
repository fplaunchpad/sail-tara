#!/usr/bin/env bash
set -euo pipefail

build_dir=$1
output_file=$(mktemp)
trap 'rm -f "$output_file"' EXIT

rocq compile -R "$build_dir" Tara -R rocq Tara -o "$build_dir/Audit.vo" rocq/Audit.v \
    >"$output_file" 2>&1 || {
    cat "$output_file"
    exit 1
}
cat "$output_file"
if grep -q '^Axioms:' "$output_file"; then
    printf '%s\n' 'Rocq proof audit failed: a published theorem depends on an axiom.' >&2
    exit 1
fi
closed_count=$(grep -c '^Closed under the global context$' "$output_file" || true)
expected_count=$(grep -c '^Print Assumptions ' rocq/Audit.v)
if [ "$closed_count" -ne "$expected_count" ]; then
    printf 'Rocq proof audit failed: expected %s closed claims, saw %s.\n' \
        "$expected_count" "$closed_count" >&2
    exit 1
fi
