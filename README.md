# TARA in Sail

A Sail model of TARA, the 16-bit teaching CPU of IIT Madras CS2300, and the toolchain generated from it. The model follows the RTL description in the [TARA Studio manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarastudio/index.html#microarch) and the [hardware manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarahw/index.html).

## Layout

| Path | Contents |
|---|---|
| `model/machine.sail` | State, memory buses, input port, framebuffer |
| `model/tara.sail` | The instruction functions (encode, decode, execute) and the order of the groups |
| `model/instructions/` | One file per instruction group: operands, encoding, semantics and description |
| `model/step.sail` | Drivers: `step`, `run_instruction`, `reset` |
| `model/syntax.sail` | Assembly syntax, for disassembly |
| `emulator/host.sail` | Host interface shared by the emulators |
| `emulator/c/`, `emulator/ocaml/` | The C and OCaml emulators: sources in `src/`, build and lint configuration beside it |
| `proofs/rocq/`, `proofs/lean/` | Proofs about the generated models: progress, the PC invariant, halting, illegal opcodes, frame conditions and the codec round trip |
| `doc/` | The specification's chapter layout and styles; its prose, listings and tables come from the model |
| `tests/` | pytest suite: the emulators against the reference model |
| `tests/programs/` | Test programs, in assembly |
| `examples/` | Programs to play: `snake.tara` |
| `tools/tara/` | `tara-asm` and the reference model with the RTL corrections below |
| `tools/sail-doc/` | Sail plugin deriving opcode fields and assembly templates for the documentation tables |
| `nix/`, `just/` | Flake packages and just recipes |

## Usage

Run everything inside `nix develop` (or direnv). `just` lists the modules and recipes, `just --list MODULE` the recipes of one module. Outputs go to `build/`.

```sh
just test                        # test both emulators; pytest options pass through, e.g. -k tara-c
just c                           # build build/c/tara-c; likewise ocaml, rocq, lean and doc
just doc                         # the specification, build/doc/tara.pdf; just doc html for tara.html
just c run prog.tara -t          # assemble a program and run it; likewise ocaml
just c play prog.tara            # assemble a program and play it in the terminal
just c play examples/snake.tara  # snake: arrow keys or WASD to steer, Q to stop
tara-asm prog.tara               # assemble to prog.bin; -o prog.hex for hex words
just format                      # format every language
just lint                        # check the formatting, Python lint and types
just ci                          # nix flake check, preserving the lock file
```

### The emulators

`tara-c` and `tara-ocaml` have the same three subcommands. Spell subcommand names in full and specify each execution option at most once; short and long aliases count as the same option. Each takes a program image: `.bin` bytes, or `.hex` words.

- `run [OPTION...] IMAGE` runs a program to its end and prints its final state (`status`, `steps`, `pc`, `r0` to `r7`, `mem`). Its options:
  - `-t`, `--trace`: print a line per step first: its PC, its instruction word, the registers after it and its disassembly.
  - `-n N`, `--max-steps N`: stop after N instructions (default 1000000; 0 for no limit).
  - `--keys K`: hold the input lines at K (0 to 31) for the whole run.
  - `--key-script FILE`: change the input lines as the run goes on, with `STEP KEYS` lines.
  - `--framebuffer`: print the framebuffer after the final state.
- `play [OPTION...] IMAGE` plays a program in the terminal: the arrow keys or WASD drive the input lines, Q drives QUIT, and Esc quits. Its options are `-n N` (no limit by default) and `--hz N`, instructions a second (default 2000; 0 for as fast as possible).
- `disasm` prints the disassembly of every 16-bit word.

`--help`, on its own or after a subcommand, lists the options. The exit status says how a run ended:

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
