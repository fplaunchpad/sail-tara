# Final presentation review: v0.4 to v0.5

## Assessment

v0.4 had the right basic architecture for this small sequential ISA. It used
native Sail registers, bidirectional mappings, and scattered definitions that
put each instruction together. A wholesale rewrite would add risk without a
clear readability gain.

It was not yet a polished presentation. Some instruction-specific rules were
hidden behind helpers, relative branches depended on a scratch-register value,
operand names varied, and support functions made readers match a type signature
to a second declaration. v0.5 makes those rules local and names consistent while
preserving the architecture, public execution API, and observations.

This is the version I would use as the readability baseline. That is a design
judgment, not a claim of uniquely optimal style or of compiler validation.

## Instruction-local meaning

The mnemonic, operand layout, and execution remain adjacent. All operand names
now have consistent roles: `rd`, `rs`, `rs1`, `rs2`, `base`, `off`, `imm`, and
`shamt`. Native execution clauses use uniform multiline blocks. The file is
longer because it is no longer optimized for the smallest line count.

The single-use `mul_low`, `shift_left`, and `shift_right` functions are removed.
Their expressions are in MUL, SHL, and SHR instead. This does **not** change the
arithmetic operations: mathematical multiplication, integer bit extraction, and
bitvector shifts still come from Sail. The full-count/zero-for-large-shifts
choice is stated visibly in both shift clauses. No arithmetic algorithm is
implemented by the model.

A helper is appropriate when it gives a shared architectural operation a useful
name, not merely when it shortens one instruction to one line. `load_word` and
`store_word` stay shared: they carry alignment, byte order, and bus behavior.

## Less reliance on driver scratch

Previously a branch read `nextPC`, relying on its initialization to `PC+2`.
Now it assigns `PC + 0x0002 + 2 * signed(off)` to `nextPC`. CALL similarly writes
`PC+2` to the link register explicitly. Both rules can be understood at the
instruction clause itself.

The equivalence argument is local. When the old worker was entered, its driver
had assigned `nextPC = (PC+2) mod 65536`. Therefore its old target expression
and the new expression denote the same word. CALL's register write does not
change PC. Intermediate wrapping in the two additions has no effect on the
final residue modulo 65536.

`nextPC` is not removed: it is a useful output of instruction execution, allowing
one common PC commit. The instruction clauses still have an internal-worker
contract. Claiming that a bare call to `execute` performs a whole retirement
would be wrong. The README makes the public boundary explicit.

## Use Sail syntax without adding an abstraction layer

Small, non-scattered helper functions put argument and result types on their
`function` declaration. Separate `val` declarations remain for the scattered
mapping and execution function. Both forms are legitimate Sail. The change is
about keeping a small helper's types and implementation together, not declaring
one legal syntax universally superior.

The existing two operator overload declarations remain aliases of Sail library
operations, not arithmetic implementations. No local sign-extension wrappers,
state monad, register snapshot/commit adapter, generic ALU framework, or macro
language is added.

## Names at the bus boundary

Calls now say `bus_read_word(PC, Fetch)` and `bus_read_word(addr, Data)` rather
than passing 0 and 2. A byte has an index 0 or 1 inside that access. The single
`event_slot` function maps this pair to the unchanged four-slot trace interface.
This does not introduce another observation representation or require clients
to migrate their event consumers.

The device addresses are named `keyboard_address` and `framebuffer_start`.
They are still the same integers. Read/write order, input snapshots, ignored
keyboard writes, and framebuffer notifications remain as before.

## What I deliberately did not simplify

**Scattered definitions.** These are a good match for a small ISA reference.
The RISC-V source also uses them, but its grouping of some instructions into
larger operation families is not a requirement for this model.

**Native state and the common driver.** Replacing them with state records again,
or adding a custom action-return language, would move away from the clear
`X(rd) = ...` form without resolving a present problem.

**Guarded word accesses and boundary outcomes.** They say something important.
Removing them, replacing them with `undefined`, or relying on exceptions to
roll back writes would change the model. The existing no-partial-write argument
still depends on the byte bus being total after alignment checking.

**Parameterized opcode evidence.** The default assignment is incomplete. A
shorter hard-coded complete decoder would be making up architectural facts.
The secondary mnemonic tags and table validation are not generic Sail features
being reimplemented; they describe this proposal's evidence boundary.

**Finite memory and a bounded trace.** The model does not need a relaxed-memory
platform, a host device framework, or an unbounded trace structure for this task.
Those could be different integration goals, not readability improvements.

## Review evidence, not execution evidence

The restricted source audit compares all 27 field layouts against the retained
baseline and checks all 55,296 tagged payloads. It also compares every execution
body against the v0.4 text after renaming parameters and explicitly accounting
for the seven intended rewrites: MUL, SHL, SHR, BZ, BN, JMP, and CALL.

Twenty instruction bodies are unchanged modulo argument names, whitespace, and
outer blocks. Seven have the exact source transformations described above.
These comparisons are source-text checks, **not semantic equivalence proofs**.
The retained finite arithmetic/alias checks evaluate equations in Python,
not the Sail instruction bodies. Deliberate changes to layouts, padding,
PUSH ordering, and ADD's arithmetic operator are detected by the audit.

The Sail arithmetic-range tests now invoke the actual instructions. They are
not reported as passing: no Sail compiler is installed. No successful Sail
parse/typecheck, backend generation, theorem proof, or TARA implementation
comparison is claimed.

## Source references

The [Sail manual](https://alasdair.github.io/manual.html) documents native state,
function declaration forms, mappings, and scattered definitions. The
[RISC-V base instruction source](https://github.com/riscv/sail-riscv/blob/master/model/extensions/I/base_insts.sail)
provides examples of instruction-centered definitions and native register access.
The [Sail vector library](https://github.com/rems-project/sail/blob/sail2/lib/vector.sail)
provides the bitvector/integer operations reused here. These are public moving
sources, not evidence of testing against an installed Sail 0.20.3 distribution.
