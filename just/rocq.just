# Rocq definitions generated from the model's core (no strings), with proofs about them.
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

# Compile proofs/rocq/Tara/NAME.v against the generated definitions and sources, as Tara.NAME.
[private]
compile name: definitions
    rocq compile -R "{{ build }}/rocq" Tara -R proofs/rocq/Tara Tara -o "{{ build }}/rocq/$1.vo" "proofs/rocq/Tara/$1.v"

# Compile what the proofs share: machines, the program logic and the PC mask.
[private]
foundations: (compile "Machine") (compile "Logic") (compile "PcMask")

# Prove that step, run_instruction and reset always complete, with exactly one outcome.
progress: foundations (compile "Progress")

# Compile the cases of step, which the theorems about it share.
[private]
cases: progress (compile "Step")

# Prove that PC stays below 0x800 through every step, reset and power-on.
invariant: cases (compile "Invariant")

# Prove that a halted CPU stays halted and unchanged until reset.
halted: cases (compile "Halted")

# Prove that opcodes 27 to 31 do not decode, and what step does with them.
illegal: cases halted (compile "Illegal")

# Prove what instructions leave alone: memory, HALTED and the PC advance.
frame: cases halted (compile "Frame")

# Prove that decoding an encoded instruction gives the instruction back.
codec: (compile "Codec")

# Compile the generated definitions, then check every proof.
[default]
build: progress invariant halted illegal frame codec audit

# Reject axioms in every published theorem.
[private]
audit: invariant illegal frame codec
    bash proofs/rocq/audit.sh "{{ build }}/rocq"

# Check that Rocq source lines fit the repository's 100-column limit.
lint:
    LC_ALL=C.UTF-8 awk 'length > 100 { print FILENAME ":" FNR ": " length " columns"; status = 1 } END { exit status }' proofs/rocq/Tara/*.v
