---
name: tara-ocaml
description: Write, refactor, and review hand-written OCaml in TARA using the repository's Core, ppx_jane, module, and tooling conventions. Read before writing or reviewing OCaml here; generated Sail output is outside the hand-written style rules.
---

# OCaml guidance

Apply these conventions to hand-written OCaml in this repository, including the emulator and compiler plugins. Use the pinned development environment and inspect the relevant dune files and interfaces before changing code.

## Modules and domain types

- Give each concept an owning module and use `Module.t`. A file module may define its own `type t`; additional concepts belong to named submodules rather than unrelated top-level types.
- Provide an `.mli` for every implementation module except `main.ml`. Expose the operations callers need and keep representation details private where appropriate.
- Represent modes, states, and outcomes with variants rather than booleans as data. Boolean predicates and the flags required by generated Sail interfaces remain ordinary booleans.
- Prefer types that express valid states over repeated run-time checks. Use named constants for fixed values and spellings.
- Keep conversions in the type's owning module, such as `Keys.Line.of_key` and `Keys.Line.of_arrow`. Use a dedicated formatting operation such as `Hex.word` for a hex value.
- Annotate record construction and destructuring explicitly, for example `({ image; max_steps; hz } : Options.t)`. Do not use module-qualified record syntax such as `Options.{ image; max_steps; hz }`.

## Libraries, strings, and error handling

- Use Core and `ppx_jane`. Emulator implementation modules open `Import`, which supplies Core with the printf APIs banned; interfaces may open Core where needed.
- Derive JSON conversion for wire records with Jane Street's `ppx_yojson_conv`, using `[@@deriving yojson_of]` when only encoding is needed. Avoid manually constructing JSON trees for records that the deriver can encode.
- Construct text with `[%string]` interpolation and write it with `Out_channel`. Do not use `^`, printf-style functions, or the `Printf` and `Format` modules. Preserve the shared import's compile-time enforcement rather than bypassing it through another module.
- Use `{|...|}` raw strings for multiline literals.
- Thread expected failures with `Or_error` and `let%bind.Or_error` or `let%map.Or_error`. Keep error handling at the appropriate boundary.
- Use low-precedence application for callbacks where it removes unnecessary parentheses, such as `Or_error.try_with @@ fun () -> ...`.
- Prefer pipelines over nested application when they make the data flow clearer.

## State and source of truth

- Thread state functionally through loops and return updated values. Keep mutation minimal and document necessary exceptions, such as flags written by signal handlers or the generated Sail model's globals.
- Use `Array.make_matrix` for two-dimensional data rather than flattening coordinates into a one-dimensional array.
- Use generated Sail functions and compiler-provided data for model behavior. Keep host concerns and presentation in the OCaml layer; changes to ISA behavior belong in Sail.
- Change the Sail source or handwritten wrapper when needed and regenerate outputs. Do not hand-edit generated Sail OCaml or apply handwritten-code warning rules to it.

## Command-line interfaces

- Use `Command_unix`, `Command.basic_or_error`, and `Command.group` for executable CLIs, with `ppx_jane` command syntax where appropriate. Library and compiler-plugin modules do not need a CLI.
- Keep commands responsible for argument conversion, diagnostics, and invoking domain operations. Keep conversions beside their owning types.
- For the TARA emulators, accept only exact `run`, `play`, and `disasm` subcommand names, including on help routes. Reject repeated execution options, including repeated aliases and mixed short/long aliases, even when their values agree.
- Preserve the shared C/OCaml exit statuses: 0 for a halted run, 1 for errors, 3 for the step limit, and 4 for an illegal opcode. Usage errors write a diagnostic to stderr and leave stdout empty. Cover changed parsing behavior in the existing parametrized CLI tests.

## Formatting, builds, and verification

- Use the pinned ocamlformat with the Jane Street profile and a 100-column margin, as configured in `emulator/ocaml/.ocamlformat`.
- Enable warnings as errors for handwritten code: `-w +a-40-42-44 -warn-error +a`. Each disabled warning must have a reason in dune. The emulator documents warnings 40 and 42 for type-directed fields and constructors used by Core/ppx_jane, and 44 for the intentional opens of operator modules.
- Treat deprecation alerts as errors with `-alert ++deprecated`; this also enforces the shared import's printf ban. Keep generated Sail modules in their separate dune stanza with their own warning policy.
- Run `just ocaml` to generate and build the emulator, `just ocaml lint` to check formatting, and `just ocaml format` when applying formatting. For other handwritten OCaml components, use their dune build and the same pinned formatting and warning policy.
- Run commands inside `nix develop` or the repository's direnv environment. Pass `--no-update-lock-file` to flake builds and checks; do not update `flake.lock` as part of OCaml work.
- Verify changed behavior through the existing pytest suite and independent reference model. Keep helpers separate from tests and programs as assembly source. Avoid golden outputs and Just recipes used as test harnesses; run checks appropriate to the change.
