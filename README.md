# TARA in Sail

A Sail model of TARA, the 16-bit teaching CPU of IIT Madras CS2300, and the toolchain generated from it. The model follows the RTL description in the [TARA Studio manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarastudio/index.html#microarch) and the [hardware manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarahw/index.html).

## Layout

| Path | Contents |
|---|---|
| `model/machine.sail` | State, memory buses, input port, framebuffer |
| `model/tara.sail` | Each instruction's operands, encoding and semantics |
| `model/step.sail` | Drivers: `step`, `run_instruction`, `reset` |
| `model/syntax.sail` | Assembly syntax, for disassembly |
| `emulator/host.sail` | Host interface shared by the emulators |
| `emulator/c/`, `emulator/ocaml/` | The C and OCaml emulators |
| `rocq/` | Runs the generated Rocq model; proves `decode (encode i) = Some i` |
| `lean/`, `doc/` | Lean project file, LaTeX document |
| `tests/` | pytest suite: the emulators against the reference model |
| `tests/programs/` | Test programs, in assembly |
| `tools/tara/` | `tara-asm`, and the reference model: TARA Studio's CPU with the RTL corrections below |
| `nix/`, `just/` | Flake packages and just recipes |

## Usage

Run everything inside `nix develop` (or direnv). `just` lists the modules and recipes, `just --list MODULE` the recipes of one module. Outputs go to `build/`.

```sh
just test                  # test both emulators; pytest options pass through, e.g. -k tara-c
just c                     # build build/c/tara-c; likewise ocaml, rocq, lean and doc
just c run prog.tara -t    # assemble a program and run it; likewise ocaml
tara-asm prog.tara         # assemble to prog.bin; -o prog.hex for hex words
just format                # format every language
just lint                  # check the formatting, Python lint and types
just ci                    # nix flake check
```

### The emulators

`tara-c` and `tara-ocaml` take a program image (`.bin` bytes, or `.hex` words) and the same options:

- `-t`, `--trace`: print a line per step: its PC, its instruction word, the registers after it and its disassembly.
- `-n N`, `--max-steps N`: stop after N instructions (default 1000000; 0 for no limit).
- `--keys K`: hold the input lines at K (0 to 31) for the whole run.
- `--key-script FILE`: change the input lines as the run goes on, with `STEP KEYS` lines.
- `--fb`: print the framebuffer after the final state.
- `--disasm-all`: print the disassembly of every 16-bit word.
- `-i`, `--interactive`: run in the terminal at `--hz` instructions a second (default 2000). The arrow keys or WASD drive the input lines, Q drives QUIT, and Esc quits.

A batch run ends by printing the final state (`status`, `steps`, `pc`, `r0` to `r7`, `mem`). The exit status says how the run ended:

- 0: the CPU halted.
- 1: an error, such as a bad option or a bad image.
- 3: the step limit was reached.
- 4: the CPU fetched an unassigned opcode.

## Website vs. TARA Studio

Where the website and the TARA Studio emulator (`taracpu` 1.2.2) disagree, the model follows the website. The reference model in `tools/tara/reference.py`, which the tests compare the emulators against, is TARA Studio's CPU with each of these corrected.

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

- Shift counts 16 to 31 (`shamt = imm8[4:0]`) shift out every bit.
- PUSH R7 stores the decremented SP, and POP R7 leaves the loaded value plus 2, following the order of the ISA table (Studio agrees).
- A word read that covers 0x5FF (LDW or a fetch at 0x5FE) gets the input lines as its low byte.
- A store to 0x5FF writes the RAM byte, which reads never return: memory has a single write port, and byte stores are read-modify-write.
- After fetching opcode 27 to 31 the model stops with `Illegal`; the control ROM that would decide what happens next is unpublished.
- Reset clears the halt latch and sets PC to 0; registers and memory keep their values.
- The input lines hold still for the duration of one instruction.
