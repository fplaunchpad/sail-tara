# Verilator emulator

- `tara-verilator` executes `emulator/state.sail`'s `host_step` through Sail-generated
  SystemVerilog and Verilator 5.052.
- The combinational `tara_step` module takes and returns the complete machine state.
- The C++ frontend uses Sail's generated C helpers for initialization, disassembly
  and text formatting. It loads images and key scripts itself.
- [CLI11](https://github.com/CLIUtils/CLI11) 2.6.2 handles options, subcommands and help.
  Repeated execution options are errors, including repetitions through aliases.
- The C emulator keeps its own frontend and build configuration.
- The adapter uses C++23. Instruction behavior stays in `model/`.
- This is an instruction emulator. CPU hardware remains deferred.

## Commands

- Run inside `nix develop --no-update-lock-file` (or direnv):

```sh
just verilator build
just verilator generate
just verilator run tests/programs/arithmetic.tara -t
just verilator play examples/snake.tara
just verilator check
just verilator lint
just test -k tara-verilator
```

- The executable is `build/verilator/tara-verilator`.
- `generate` writes `tara.sv` and its support include, `sail_modules.sv`, into that directory.
- Source changes trigger regeneration during CMake configuration and rebuild the circuit.
- `check` verifies complete state transfer, both RAM boundaries, halted-state preservation
  and illegal-opcode advancement with assembly programs.
- `just test` runs CLI, disassembly, terminal and reference-model tests across all three emulators,
  including Hypothesis-generated programs, traces, key scripts and framebuffer output.
- The Nix package installs the executable in `bin/` and SystemVerilog files in
  `share/tara-verilator/`.
- See the [top-level README](../../README.md) for options and exit statuses.

## Adapter

- `LoadInputs` copies the C helper state into the generated module's input ports.
- `Machine::Step` evaluates the combinational module once.
- `StoreOutputs` copies its results back for the shared frontend to print and inspect.
- The adapter never calls the C model's instruction execution functions.
- Authored C++ uses strict warnings, clang-tidy and clang-format. Include groups are
  standard headers, generated/external headers, then project headers.
- Tests build one asymmetric state fixture, then arrange, execute and assert each case.
- `src/` groups responsibilities into machine state, input files, CLI options, run status,
  key events, terminal lifetime and interactive play.

## Sail backend patch

- [sail-sv-reachability.patch](../../nix/patches/sail-sv-reachability.patch) changes only
  Sail 0.20.3's SystemVerilog backend.
- The original backend repeatedly expands branch conditions at joins in the generated
  instruction codec. The patch shares them through one reachability signal per block.
- Phi inputs and assertions use those signals. Assertions remain enabled.
- Sail's SystemVerilog optimization passes are disabled to keep the shared signals;
  Verilator optimizes the resulting circuit.
- Unions become structs, state ports use fixed arrays, and Sail's dynamic memory
  implementation is disabled.
- Nix builds Verilator itself with C++17 to match SystemC's API in its smoke tests.
  This does not change the adapter's C++23 standard.
