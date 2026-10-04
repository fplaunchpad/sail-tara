# TARA in Sail

**Reference proposal v0.5.** Start with [`tara.sail`](tara.sail). Each instruction
has one operand declaration, one bidirectional field mapping, and one execution
clause. The source is intended for Sail 0.20.3; native compiler validation is
still outstanding. The architectural profile is a proposal, not a claim of
agreement with TARA Studio or RTL. See [PROFILE.md](PROFILE.md).

## Read the model

Read `tara.sail` for instruction meaning, `machine.sail` for the register and
memory primitives it uses, and `step.sail` for retirement. `encoding.sail` is
needed only when reasoning about numeric instruction words.

| Notation | Meaning in this model |
|---|---|
| `word`, `byte` | Exactly 16 and 8 bits respectively. |
| `rd`, `rs`, `rs1`, `rs2` | Destination and source register indices. |
| `X(r)` / `X(r) = value` | Read / write register r. R0 is writable. |
| `signed(v)` / `unsigned(v)` | Interpret bits as a mathematical integer. |
| `a @ b` | Concatenate bits, a above b. |
| `get_slice_int(16, p, 0)` | Extract the low 16 bits of integer p. |
| `PC` | Address of the current instruction, until retirement. |
| `nextPC` | Proposed successor address, initialized by the driver. |
| `lr`, `sp` | Register indices R6 and R7, not separate registers. |

For example, this is the complete arithmetic effect of ADD:

```sail
function clause execute ADD(rd, rs1, rs2) = {
  X(rd) = X(rs1) + X(rs2)
}
```

Word-sized addition wraps modulo 65536. Source register values are read before
the destination is written. CALL states its link and target without relying on
an earlier value of the driver's proposed successor:

```sail
function clause execute CALL(off) = {
  X(lr) = PC + 0x0002;
  nextPC = PC + 0x0002 + 2 * signed(off)
}
```

All instruction clauses leave architectural PC unchanged. Successful retirement
commits `nextPC` once; HLT also reaches that commit. RET does not check its target
alignment: the next binary fetch checks it.

## Entry points

```sail
run_instruction(env, insn)       /* One decoded instruction attempt. */
step(env)                        /* Fetch with the evidenced opcode table. */
step_with(env, table)             /* Fetch with a supplied partial table. */
encode(insn)                     /* Instruction to word, or boundary. */
decode(raw)                      /* Word to instruction, or boundary. */
```

The execution entries update native Sail registers and return `Retired()`,
`Stopped()`, or `NeedsSpecification(reason)`. Codec calls return their result or
raise the internal `SpecificationBoundary` exception. The drivers catch this
exception; it is **not** a TARA hardware trap and does not provide rollback.

`execute` and `retire` are internal workers. Do not use `execute` directly as a
whole-instruction entry: the driver supplies halt checks, the input snapshot,
cleared observations, successor initialization, and PC commit.

The architectural state is `(GPR, PC, MEM, HALTED)`. Initialize all four before
execution. No physical-reset values are assumed. `Platform`, `Events`, and
`nextPC` are auxiliary model state. Tests provide fixture-only `zero_state`,
`install_state`, and `snapshot` helpers; the production semantics has no second
state-transition implementation.

## Memory, observations, and unresolved behavior

Memory has 2048 bytes, selected by the low 11 logical-address bits. Fetch uses
live memory, so stores can change later instructions. Words are big-endian in
this proposed profile. Odd fetch and word addresses are model boundaries,
not invented guest exceptions.

Use `PlainRAM()` for RAM without devices. `KeyboardFramebuffer(keys)` fixes a
five-bit input snapshot for one attempt. The exact device policy and its
limitations are in PROFILE.md.

Internal bus calls distinguish `Fetch` and `Data`. Only `event_slot` translates
those roles and byte indices into the existing four-slot public `Events` vector:
fetch occupies 0,1; data occupies 2,3. Read **indices in that order**, dropping
`None()`. This preserves previous trace consumers. Fetch observations survive a
later decode or data-alignment boundary. The architecture is unchanged at a
boundary; the auxiliary observation state need not be.

The default numeric opcode table remains deliberately partial. Operand-field
layouts are specified for all 27 instructions. No new opcode assignments, shift
policies, stack-alias rules, or exception behavior are introduced by this
readability revision.

## Build and checks

With Sail installed:

```sh
make check
make test SAIL_LIB_DIR=/path/to/the/matching/sail/lib
make rocq
```

`make check` asks Sail to check both the model and its tests. `make test` generates
C, compiles it against the matching Sail runtime, and runs the native test
program. `make rocq` requests definition generation, not a proof or a Rocq build.
Those targets have **not** succeeded in this environment: Sail is unavailable.

```sh
make audit
```

This separate Python command performs restricted source-text and field-layout
checks. It is not a Sail parser, typechecker, interpreter, or correctness oracle.
See [validation/README.md](validation/README.md) for the exact results and limits.

## Review and dependencies

[REVIEW.md](REVIEW.md) explains why this revision keeps the v0.4 architecture
rather than replacing it again. There are no generated instruction definitions,
custom arithmetic algorithms, compatibility aliases, or architecture-name
identifier prefixes. Only the Sail prelude is required by the model itself.

The eleven Sail test groups cover all mnemonics, aliases, boundaries, arithmetic,
codecs, the published binary fixture, live-memory fetch, and device observations.
Arithmetic-range tests now go through the actual SHL, SHR, and MUL instructions,
not removed helpers. These native groups are authored but unrun.
