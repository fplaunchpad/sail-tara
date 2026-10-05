# TARA in Sail

- A Sail model of TARA, the 16-bit teaching CPU of IIT Madras CS2300, with a generated toolchain.
- The model follows the RTL description in the [TARA Studio manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarastudio/index.html#microarch) and the [hardware manual](https://www.cse.iitm.ac.in/~ayon/courses/CS2300/taramanual/tarahw/index.html).

## Layout

- `model/machine.sail`: state, memory buses, input port and framebuffer.
- `model/tara.sail`: instruction union, codec and execution dispatch.
- `model/instructions/`: operands, encodings, semantics and descriptions by instruction group.
- `model/step.sail`: stepping, instruction execution and reset drivers.
- `model/syntax.sail`: assembly syntax used by disassembly.
- `emulator/state.sail`: shared state interface and exported `tara_step` module.
- `emulator/host.sail`: shared assembly syntax and text formatting.
- `emulator/c/`, `emulator/ocaml/`, `emulator/verilator/`: the three emulator frontends.
- `proofs/rocq/`, `proofs/lean/`: proofs about progress, PC, halting, illegal opcodes,
  frame conditions and codec round trips.
- `doc/`: specification layout and styles; content comes from the model.
- `tests/`: CLI, terminal and reference-model comparisons; assembly fixtures in `tests/programs/`.
- `examples/`: programs to play, including `snake.tara`.
- `tools/tara/`: assembler and corrected reference model.
- `tools/sail-doc/`: Sail plugin that extracts instruction metadata for the specification.
- `nix/`, `just/`: packages, checks and build recipes.

## Usage

- Run everything inside `nix develop --no-update-lock-file` (or direnv).
- `just` lists the modules and recipes; `just --list MODULE` lists one module's recipes.
- Outputs go to `build/`, or the directory set by `TARA_BUILD`.

```sh
just test                        # test all three emulators; pytest options pass through
just c                           # build build/c/tara-c; likewise ocaml and verilator
just verilator                   # build build/verilator/tara-verilator
just doc                         # the specification, build/doc/tara.pdf; just doc html for tara.html
just c run prog.tara -t          # assemble and run; likewise ocaml and verilator
just c play prog.tara            # assemble a program and play it in the terminal
just c play examples/snake.tara  # snake: arrow keys or WASD to steer, Q to stop
tara-asm prog.tara               # assemble to prog.bin; -o prog.hex for hex words
just format                      # format every language
just lint                        # check the formatting, Python lint and types
just ci                          # nix flake check, preserving the lock file
```

### The emulators

- `tara-c`, `tara-ocaml` and `tara-verilator` share the three subcommands below.
- Spell subcommand names in full and specify each execution option at most once;
  short and long aliases count as the same option.
- Program images contain `.bin` bytes or `.hex` words.
- `tara-verilator` executes Sail-generated SystemVerilog through Verilator 5.052.
  Its [README](emulator/verilator/README.md) covers generation and the Sail backend patch.
- Its C++ frontend uses CLI11; the C and OCaml frontends keep their existing parsers.
- Nix exposes all three emulators as packages and apps, for example
  `nix run --no-update-lock-file .#tara-verilator -- --help`.

- `run [OPTION...] IMAGE` runs a program to its end and prints its final state (`status`, `steps`, `pc`, `r0` to `r7`, `mem`). Its options:
  - `-t`, `--trace`: print a line per step first: its PC, its instruction word, the registers after it and its disassembly.
  - `-n N`, `--max-steps N`: stop after `N` instructions (default `1000000`; `0` for no limit).
  - `--keys K`: hold the input lines at `K` (`0` to `31`) for the whole run.
  - `--key-script FILE`: change the input lines as the run goes on, with `STEP KEYS` lines.
  - `--framebuffer`: print the framebuffer after the final state.
- `play [OPTION...] IMAGE` plays a program in the terminal: the arrow keys or `W` `A` `S` `D` drive the input lines, `Q` drives `QUIT`, and `Esc` quits. Its options are `-n N` (no limit by default) and `--hz N`, instructions a second (default `2000`; `0` for as fast as possible).
- `disasm` prints the disassembly of every 16-bit word.

- `--help`, on its own or after a subcommand, lists the options.
- The exit status says how a run ended:

- `0`: the CPU halted.
- `1`: an error, such as a bad option or a bad image.
- `3`: the step limit was reached.
- `4`: the CPU fetched an unassigned opcode.

## Website vs. TARA Studio

- Where the website and TARA Studio (`taracpu` 1.2.2) disagree, the model follows the website.
- Tests compare all three emulators against `tools/tara/reference.py`: TARA Studio's CPU
  with the corrections below.

|                                        | Website (RTL)                              | TARA Studio                            |
| -------------------------------------- | ------------------------------------------ | -------------------------------------- |
| Word access or fetch at an odd address | bit 0 ignored: `word index = addr >> 1`    | bytes `addr` and `addr + 1`            |
| Word access or fetch at `0x7FF`        | the word at `0x7FE`                        | error; the CPU halts                   |
| `CALL` at `0x7FE`                      | links `0x000`: PC is "masked to `0x7FF`"   | links `0x800`                          |
| Reading `0x5FF`                        | the live input lines                       | RAM, rewritten by the UI on key events |
| Opcodes 27–31                          | fetched like any word, so `PC + 2`         | error; the CPU halts, PC unchanged     |
| `Q` key                                | requests a reset; `QUIT` is switch `sw[4]` | sets `QUIT` (bit 4 of `0x5FF`)         |

## Assumptions

Where the website is silent, the model assumes:

- Shift counts 16 to 31 (`shamt = imm8[4:0]`) shift out every bit.
- `PUSH R7` stores the decremented SP, and `POP R7` leaves the loaded value plus 2, following the order of the ISA table (Studio agrees).
- A word read that covers `0x5FF` (`LDW` or a fetch at `0x5FE`) gets the input lines as its low byte.
- A store to `0x5FF` writes the RAM byte, which reads never return: memory has a single write port, and byte stores are read-modify-write.
- After fetching opcode 27 to 31 the model stops with `Illegal`; the control ROM that would decide what happens next is unpublished.
- Reset clears the halt latch and sets PC to `0`; registers and memory keep their values.
- The input lines hold still for the duration of one instruction.
