# C emulator

The C emulator puts a native command-line and terminal interface around the Sail model. Sail generates the CPU implementation from `model/` and `emulator/host.sail`; CMake compiles that output with Sail's C runtime and links the host-side C sources in `src/`. The C sources handle image loading, options, batch execution, tracing, disassembly output and interactive terminal input/display.

The host interface is shared with the OCaml emulator. Keep CPU behavior in Sail and host-specific behavior in `src/`; changes to model semantics belong in `model/` or `emulator/host.sail`.

From the repository root inside `nix develop` (or direnv):

```sh
just c build
just c run tests/programs/arithmetic.tara
just c play tests/programs/pixels.tara
just c lint
just test -k tara-c
```

The executable is written to `build/c/tara-c`. See the [top-level README](../../README.md) for the shared command-line options and exit statuses.
