# Agent instructions

The global `python`, `just`, `ocaml` and `cpp` skills hold the language rules. This file holds what is specific to this repository; the [README](README.md) describes the layout and the commands.

## Environment

- Work inside `nix develop` (or direnv). Pass `--no-update-lock-file` to flake commands, and leave `flake.lock` alone unless asked.
- Every language uses 100 columns: Black, Ruff, ocamlformat, clang-format, and `sail --fmt` through `sail_config.json`.
- The Sail model in `model/` is the source of truth. Change behaviour there and regenerate; never edit generated C, OCaml, Rocq or Lean.
- Just is pinned at 1.58.0. Its modules live in `just/`; each imports `just/settings.just` and sets `working-directory := ".."`.

## Python

- Runtime dependencies (`[project] dependencies`) and test dependencies (`[tool.tara] test-dependencies`) in `pyproject.toml` are pinned to the releases nixpkgs provides; the Nix build refuses to evaluate when a pin drifts. uv locks the same releases for Ruff, Black and Pyright.
- Check with `just python lint`, `just python format --check` and `just python typecheck`; apply formatting with `just python format`.
- TARA Studio's modules are untyped; their stubs live in `typings/`.
- Enums whose values are their names derive from `tara.assembly.Named`.

## Tests

- `just test` runs the pytest suite against both emulators; pytest arguments pass through (`just test -k tara-c`).
- Expected results come from the reference model (`tools/tara/reference.py`, TARA Studio's CPU with the RTL corrections the README lists) or from explicit assertions. There are no golden files, and no tests of the Sail model itself: it is the source of truth.
- Test programs are TARA assembly, assembled at test time; random programs come from the Hypothesis strategies in `tools/tara/strategies.py`.

## Emulators

- `tara-c` and `tara-ocaml` share one command line: the subcommands `run`, `play` and `disasm`, matched exactly (no abbreviations, also after `--help`). A repeated option is an error, even with the same value or through another alias.
- Exit statuses: 0 halted, 1 error, 3 step limit, 4 illegal opcode. An error prints a message on stderr and nothing on stdout.
- C (`emulator/c`): strict C11 through CMake with every warning an error, and clang-tidy's best-practice families as errors (`just c lint`); disable a check only with its reason in `.clang-tidy`. Functions that act are named verb first (`parse_options`), sum types are tagged unions, results return by value, conditions with side effects get an explicit `if`/`else`, and nothing is cast to `(void)`.
- OCaml (`emulator/ocaml`): implementation modules open `Import`, which bans the printf family.
