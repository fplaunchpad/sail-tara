# OCaml emulator

The OCaml emulator combines Sail-generated CPU code with hand-written Core modules for its command
line, image loading, batch execution, tracing, disassembly and interactive terminal interface. Sail
generates `build/ocaml/src/tara.ml` from `model/` and `emulator/host.sail`; Dune overlays the project
from this directory and compiles it with the pinned OCaml toolchain, Core and `ppx_jane`.

The host interface is shared with the C emulator. Keep instruction and machine semantics in Sail,
and keep the OCaml-specific host behavior in `src/`. The generated file lives under `build/` and is
recreated from the model; do not edit it directly.

From the repository root inside `nix develop` (or direnv):

```sh
just ocaml build
just ocaml run tests/programs/arithmetic.tara
just ocaml play tests/programs/pixels.tara
just ocaml lint
just test -k tara-ocaml
```

The executable is written to `build/ocaml/tara-ocaml`. See the
[top-level README](../../README.md) for the shared command-line options and exit statuses.
