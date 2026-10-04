# TARA in Sail

A Sail model of TARA, the 16-bit teaching CPU of IIT Madras CS2300, and the
toolchain generated from it. The model follows the RTL description in the
[TARA Studio manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarastudio/index.html#microarch)
and the [hardware manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarahw/index.html).

## Layout

| Path | Contents |
|---|---|
| `model/machine.sail` | State, memory buses, input port, framebuffer |
| `model/tara.sail` | Each instruction's operands, encoding and semantics |
| `model/step.sail` | Drivers: `step`, `run_instruction`, `reset` |
| `model/syntax.sail` | Assembly syntax, for disassembly |
| `tests/` | Sail test suite |
| `tools/tara/` | Python tools built on TARA Studio's assembler |
| `nix/`, `just/` | Flake packages and just recipes |

## Usage

Run inside `nix develop` (or direnv); `just` lists every recipe.

```sh
just check            # typecheck the model and tests
just test             # run the Sail test suite through the C backend
just format           # format the Sail sources (sail --fmt, 100 columns)
just lint             # check Sail formatting and line width
tara-asm prog.tara    # assemble to prog.bin (-o prog.hex for text)
just python lint      # also: format, typecheck
```

## Website vs. TARA Studio

Where the website and the TARA Studio emulator (`taracpu` 1.2.2) disagree,
the model follows the website.

| | Website (RTL) | TARA Studio |
|---|---|---|
| Word access or fetch at an odd address | bit 0 ignored: "word index = addr » 1" | bytes addr and addr+1 |
| Word access or fetch at 0x7FF | the word at 0x7FE | error; the CPU halts |
| CALL at 0x7FE | links 0x000: PC is "masked to 0x7FF" | links 0x800 |
| Reading 0x5FF | the live input lines | RAM, rewritten by the UI on key events |
| Opcodes 27–31 | fetched like any word, so PC + 2 | error; the CPU halts, PC unchanged |
| Q key | requests a reset; QUIT is switch sw[4] | sets QUIT (bit 4 of 0x5FF) |

## Assumptions

Where the website is silent, the model assumes:

- Shift counts 16–31 (`shamt = imm8[4:0]`) shift out every bit.
- PUSH R7 stores the decremented SP and POP R7 leaves the loaded value plus 2,
  following the order of the ISA table (Studio agrees).
- A word read that covers 0x5FF (LDW or fetch at 0x5FE) gets the input byte as
  its low half.
- A store to 0x5FF writes the RAM byte, which reads never return. Memory has a
  single write port and byte stores are read-modify-write.
- After fetching opcode 27–31 the model stops with `Illegal`; the control ROM
  that would decide what happens next is unpublished.
- Reset clears the halt latch and sets PC to 0; registers and memory keep
  their values.
- The input lines hold still for the duration of one instruction.
