# TARA reference profile and evidence

This ledger accompanies proposal v0.5. The v0.4 architectural and observation
profile is retained, including the four trace slots and native Sail registers. The
source is not compiler-validated or implementation-verified.

## Sources

- [TARA Studio manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarastudio/index.html): Instruction Set, Memory Layout, and Microarchitecture Advanced.
- [TARA hardware manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarahw/index.html): published Fibonacci machine words, expected registers, and memory/monitor descriptions.
- [Sail language manual](https://alasdair.github.io/manual.html): functions, state, vectors, records, union patterns, and compilation commands.
- [Sail standard-library vector definitions](https://github.com/rems-project/sail/blob/sail2/lib/vector.sail): source reviewed for bitvector, shift, extension, and vector primitives. This is a moving branch, not a validated installation of the target version.
- [Sail standard-library arithmetic definitions](https://github.com/rems-project/sail/blob/sail2/lib/arith.sail): source reviewed for mathematical integer multiplication. The same installation qualification applies.
- [Sail RISC-V](https://github.com/riscv/sail-riscv): reference for separating instruction syntax, execution, encoding, and platform behavior.

## Architectural scope

One step represents one instruction retirement, not a microcycle. State is eight
writable 16-bit registers, a 16-bit logical PC, 2,048 bytes of unified memory,
and a halted bit. R6 and R7 are ordinary writable registers with link and stack
roles in specific instructions. R0 is not a constant zero register. Conditions
are evaluated from register values, not a separate architectural flag register.

GUI controls, debugging LEDs, cycle counters, UART loading, cache behavior,
interrupts, reset sequencing, and an assembly-text parser are not modeled.
The initial state and, when relevant, input snapshots are supplied externally.

## Chosen policies and their limitations

| Question | This Sail profile | Status |
|---|---|---|
| Arithmetic | Fixed-width 16-bit modular results; signed SLT and signed ADDI immediate | Formalization of documented instructions |
| Logical PC | Wrapping 16-bit PC, not an 11-bit register | Explicit profile choice consistent with return-value width |
| Memory addressing | Each byte address uses the low 11 logical-address bits | Based on documented MAR behavior |
| Word byte order | Big-endian for fetch and data | Completion choice supported, but not settled, by monitor/UART examples |
| Word/fetch alignment | Odd addresses produce `NeedsSpecification` without architectural mutation | Model boundary, not a claimed hardware exception |
| Relative control flow | Old PC + 2 + twice the sign-extended offset | Based on documented post-fetch base |
| Memory offsets | Unscaled signed 5-bit byte offset, -16 through +15 | Follows instruction description, not inconsistent game-example prose |
| Shift count | Entire unsigned 8-bit field; counts >=16 produce zero | Completion choice; not verified against actual shift hardware |
| PUSH R7 | Decrement R7, then read the operand; store the new R7 | Explicit sequential alias policy, not implementation-confirmed |
| POP R7 | Load into R7, then increment that R7 by two | Explicit sequential alias policy, not implementation-confirmed |
| CALL/RET | CALL writes R6 and branches; RET reads R6; no hidden stack operation | Formalization of documented link-register mechanism |
| HLT | Retires, advances PC by two, sets halted | Subsequent steps return Stopped without another retirement |
| Padding bits | Canonical zero padding only | Other patterns produce a model boundary, not a hardware-trap claim |
| Opcode table | Caller-supplied injective partial assignment | Default contains only seven evidenced assignments |
| Reset | Initial state supplied; zero-state helper only in test harness | No claim about physical reset values |

A different edge policy defines a different reference profile; changing such
behavior is not merely an editorial correction. In particular, do not substitute
RISC-V zero-register, shift-count-masking, or exception rules without evidence.

## Operand and state ordering

Ordinary instruction source operands, including a base register aliased with a
load/store data register, are read from the old state. Only the specified
PUSH/POP R7 policy uses a sequential intermediate register value. Word alignment
is checked before architectural PC, register, or data-memory changes. Driver scratch `nextPC` is initialized to old PC plus two; taken control
flow overwrites that default. Only retirement commits it to architectural PC.
PUSH computes the value corresponding to the sequential R7 policy, then performs
the checked store before writing SP. With this total byte bus, that preserves
the retired state and observations while avoiding a rollback requirement.

The decoded `run_instruction` entry does not fetch and does not validate PC
alignment. The binary `step_with` entry does. This distinction makes it
possible to reason about instruction effects independently of fetchability.

Instruction fetch reads live memory. A proof using an immutable program map must
justify that program bytes are unchanged, including writes through high-address
aliases that reach those same physical bytes.

## Optional platform policy

`PlainRAM()` treats every byte as ordinary RAM and emits no device events.
`KeyboardFramebuffer(keys)` supplies a fixed five-bit keyboard snapshot for one
whole step. Reading physical byte 0x05FF returns that snapshot zero-extended to
one byte. Writes there leave the underlying RAM byte unchanged. Writes to bytes
0x0600 through 0x07FF update RAM and report framebuffer events. Word accesses
compose byte operations in big-endian order, including overlaps with devices.

These are proposed byte-bus policies, not full hardware-device conformance
claims. Input bit meanings, debouncing, time, and host key delivery are outside
the model. Both instruction and data fetches use the same byte-bus adapter.

The event vector has four optional slots. Indices 0 and 1 are the first and
second fetch-byte observations; indices 2 and 3 are the first and second data
byte observations. The logical trace is obtained by visiting **indices 0,1,2,3
in that order** and dropping `None()`. It is not obtained by blindly iterating
a descending-index Sail vector's printed element order. RAM operations leave
slots empty, and decoded execution has no fetch slots.

A decode or data-alignment boundary preserves architectural state but retains
any input observation already made during fetch. An odd-PC boundary, invalid
opcode-table boundary, or already-halted state performs no fetch. Data word
helpers check alignment before either byte access. The byte bus has no later specification-boundary failures. In load, store, PUSH and POP
clauses, all possibly failing operations precede architectural writes.

`SpecificationBoundary` is a Sail language exception used for control flow, not
a TARA architectural exception. The driver catches it as `NeedsSpecification`;
catching it does not itself undo any writes. The unchanged-state property is
about the architectural projection `(GPR, PC, MEM, HALTED)`, not every component
of the generated Sail state. `nextPC`, `Platform` and `Events` are auxiliary
model state. Fetch observations are deliberately retained on later boundaries.

For whole-program reasoning, choose an external input sequence or quantify
over permitted sequences. Source/target comparison should relate observable
reads, not simply use identical instruction numbers when the compiler changes
instruction counts.

## Evidence for default opcodes

The hardware manual's Fibonacci fixture supplies these words and relevant
mnemonics: `1A00` (LIL), `A505` (BZ), `4C4C` (ADD), `1260` (MOV), `5DFF`
(ADDI), `B7FA` (JMP), and `0800` (HLT). Their high five bits establish:

```
HLT=1, MOV=2, LIL=3, ADD=9, ADDI=11, BZ=20, JMP=22.
```

All 27 field formats are implemented. The remaining opcode numbers still need
an evidence-backed assignment. Tests supply a fixed synthetic complete assignment
to exercise all fields; that table is **not an architectural assertion**.

## Intended proof obligations — not proved here

Under this explicit profile, useful first goals are determinism for a fixed
environment and table; width/index preservation; the unchanged-state property
of boundaries; canonical codec round trips; old-state operand behavior; and
agreement with the previous explicit-state profile under the architectural-state
projection. There is no longer a separate architectural-register adapter. These
should be proved over definitions generated from the Sail source, not over an unrelated hand-written emulator.

A compiler theorem additionally needs an observation relation, a source
semantics, simulation or refinement arguments, and a proof that generated code
does not reach specification boundaries under the theorem's hypotheses.
None of these proofs, Rocq exports, or implementation-comparison results is
included or claimed in this delivery.
