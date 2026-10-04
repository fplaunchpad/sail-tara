# Handoff: TARA in Sail

This is a handoff from a Claude Code session to whoever continues the work, for example Codex. Read it fully before changing anything; the "User preferences" section is as important as the task list.

## The project

A Sail model of TARA, the 16-bit teaching CPU of IIT Madras CS2300, and the toolchain generated from it: C and OCaml emulators, Rocq, Lean and Lem definitions, and a typeset specification. The model follows the RTL description on the course website (the TARA Studio manual's microarchitecture section and the hardware manual); where the website is silent, the ISA reference table. The README lists every discrepancy with TARA Studio's emulator (`taracpu` 1.2.2) and every assumption.

- Repository: `/home/nandhagk/Projects/tara`, remote `origin` = https://github.com/nandhagk/tara.git
- Branch: `tara-toolchain` (all work is here; `main` has not been touched). Push after every commit.
- Toolchain (pinned in the flake): Sail 0.20.3 (patched, see below), OCaml 5.5, Rocq 9.3.0, Lean 4.29.0 with lean-sail v6, Lem (nixpkgs `ocamlPackages.lem`), Python 3.15.0rc2, just 1.58, CMake + Ninja, clang-tools 21.
- Everything runs inside `nix develop` (or direnv). Never run `nix flake update`; pass `--no-update-lock-file` to `nix build`/`nix flake check`. Flakes see only git-tracked files: `git add` new files before a nix build.

## Layout

| Path | Contents |
|---|---|
| `model/machine.sail`, `step.sail` | State, buses, input port, framebuffer; the drivers `step`, `run_instruction`, `reset` |
| `model/tara.sail` | Scattered `encode`/`decode`/`execute`, the group includes, the catch-all `decode` |
| `model/instructions/*.sail` | One file per ISA group: each instruction's union, encode, decode, execute clauses and doc comment |
| `model/syntax.sail` | Assembly syntax: scattered `assembly`, a clause per instruction |
| `emulator/host.sail` | Host interface shared by the emulators (all text is formatted in Sail) |
| `emulator/c/` | C emulator: `CMakeLists.txt`, `.clang-format`, `.clang-tidy`, sources in `src/` |
| `emulator/ocaml/` | OCaml emulator: dune project, sources in `src/` (Core, Command, ppx_jane) |
| `rocq/` | `Run.v` (runs the generated monad), `Smoke.v`, `Codec.v` (proof of `decode (encode i) = Some i`) |
| `lean/` | `smoke.sail`: a Sail `main` built into a Lean executable (Fibonacci) |
| `lem/` | OCaml driver for the Lem extraction (`smoke.ml`) |
| `doc/tara.tex` | LaTeX frame of the specification; the body is generated |
| `tools/tara/` | Python library: `asm.py` (tara-asm), `reference.py` (reference model), `emulator.py`, `transcript.py`, `keys.py`, `isa.py`, `image.py`, `assembly.py` (typed TARA assembly), `strategies.py` (Hypothesis), the specification generator (`specification.py`, `sail_doc.py`, `document.py`, `instructions.py`, `prose.py`, `latex.py`, `asciidoc.py`) |
| `tests/` | pytest suite; `tests/helpers/`; `tests/programs/*.tara` |
| `typings/` | Stubs for TARA Studio's untyped modules |
| `just/`, `justfile` | just modules: `model`, `c`, `ocaml`, `rocq`, `lean`, `lem`, `doc`, `python` |
| `nix/` | Packages, checks, dev shell; `nix/patches/sail-lem-register-keywords.patch` |

## Commands

```sh
just                      # list modules and root recipes; just --list c lists a module
just build                # every artifact
just test                 # pytest suite against build/c/tara-c and build/ocaml/tara-ocaml; -k tara-c narrows
just lint                 # Sail, C (clang-format + clang-tidy), OCaml, Lem driver, Python (ruff, black, pyright)
just format
just c / just c run PROG.tara [OPTION...] / just c play PROG.tara
just ocaml, just rocq, just lean, just lean smoke, just lem, just lem smoke, just doc, just doc html
just python lint | format --check | typecheck | sync | lock-check
just ci                   # nix flake check -L
```

The test suite runs on the Nix Python environment `$TARA_PYTHON` (the dev shell sets it), not uv: Hypothesis publishes no wheels for Python 3.15. uv manages only the linters; pyright resolves imports with `--pythonpath "$TARA_PYTHON"`. Pass emulators to pytest as `--emulator=PATH`, with `=`.

## The testing approach

- The suite in `tests/` runs every emulator against an in-process reference model, `tools/tara/reference.py`: TARA Studio's CPU with the RTL corrections (one override each, matching the README's discrepancy table). Expected values come from the reference or from explicit assertions, never from stored outputs. There are no golden files and no hex programs; test programs are assembly, assembled at test time.
- `test_cli.py`: the command line. `test_programs.py`: `tests/programs`, TARA Studio's 27 examples (with key scripts), and Hypothesis-generated programs that always halt (from `tara.strategies`, shrinking on failure). `test_disasm.py`: `disasm` against TARA Studio's assembler and opcode table. `test_interactive.py`: `play` through a pseudo-terminal. `test_doc.py`: the generated specification.
- The model itself has no unit tests: it is the specification, validated by agreement with the independent reference through the emulators.

## The emulators' command line

```
tara-{c,ocaml} run [-t|--trace] [-n|--max-steps N] [--keys K] [--key-script FILE] [--framebuffer] IMAGE
tara-{c,ocaml} play [-n|--max-steps N] [--hz N] IMAGE
tara-{c,ocaml} disasm
```

Exit statuses: 0 halted, 1 error (usage, image, key script, terminal; message on stderr, nothing on stdout), 3 step limit, 4 illegal opcode. `tests/` and the README describe the rest (output format, key scripts, the interactive screen and keys).

## Status

Done and pushed on `tara-toolchain` (HEAD `beb1d1f`):

- Model v0.6 (RTL-conformant), split by ISA group, documented with doc comments.
- `tara-c`: full command line with subcommands, interactive mode, CMake build, all warnings as errors, clang-tidy best-practice checks clean. Passes the whole suite.
- `tara-ocaml`: full command line and interactive mode with the old flag syntax (`-i`, `--disasm-all`, `--fb`). It FAILS the suite's subcommand tests until the rework below lands.
- The test suite, reference model, typed assembly, Hypothesis strategies.
- Rocq: generated definitions, a Fibonacci run by `vm_compute`, and the codec round-trip proof.
- Lean: generated definitions and an executable Fibonacci smoke test.
- Lem: generated, typechecked with `lem -wl err`, OCaml extraction runs Fibonacci. Needs the local Sail patch (below).
- The specification is generated from the model: PDF (LaTeX) and HTML (AsciiDoc), `just doc` and `just doc html`.
- `nix flake check` passes every check except `tests`, which fails only on `tara-ocaml`'s missing subcommands.

## Unfinished work, in order

Agent branches are local git worktrees under `.claude/worktrees/`; each agent was told to commit its work in progress as a `wip:` commit on its branch. Inspect a branch with `git log tara-toolchain..BRANCH` and `git diff tara-toolchain...BRANCH`; merge with `git merge --squash BRANCH`, check, commit, push. Remove merged worktrees afterwards (`git worktree remove`, `git branch -D`).

1. **OCaml rework** (`worktree-agent-a94465c609e3c3990`). Rebase on `tara-toolchain`, finish, and make `just test -k tara-ocaml`, `just lint` and `nix build .#tara-ocaml .#tara-lem` pass. It must:
   - switch to the subcommands `run`/`play`/`disasm` with Core's `Command.group` (delete the cross-flag checks; `--fb` becomes `--framebuffer`), and add `run`/`play` recipes to `just/ocaml.just` as in `just/c.just`;
   - replace booleans as data (fields, parameters, returns) with variants, e.g. `Machine.Pixel.t = Lit | Dark`, `Cpu.t = Running | Halted`, `Terminal.check : unit -> unit Or_error.t`;
   - make state functional (`Run.step`, `Keyboard.feed`, `Display.draw`, `Framebuffer.refresh` return new values; the frame loop threads state); only the Sail model's globals and signal-handler flags stay mutable, each with a comment;
   - ban printf and friends: an `Import` module (`include Core`, shadow `printf`/`sprintf`/`eprintf`/`ksprintf`/`failwithf`/`Printf`/`Format` with `[@@deprecated]`), `open! Import` everywhere, `-alert ++deprecated` in dune; a `Hex` module for 4-digit hex;
   - move `line_of_letter`/`line_of_arrow` into `Keys.Line.of_key`/`of_arrow`; annotate record construction as `({ ... } : Module.t)`; prefer pipelines;
   - apply the same rules to `lem/smoke.ml`.
2. **Rocq properties** (`worktree-agent-a95442f43f0e29961`), replacing the smoke tests: progress (totality and determinism of `step`), preservation of `wf s := PC < 0x800`, halting is absorbing, `decode w = None` exactly for opcodes 27–31 and the illegal step's effect, frame conditions (stretch). Keep `Codec.v`. Check `Print Assumptions`.
3. **Lean properties: done, not merged** (`worktree-agent-a92a25b034e0f16f9`, commit `01c261e`).
   - Proved, with no `sorry`; a build-time `#standard_axioms` check rejects one:
     - progress: `step_progress`;
     - preservation: `step_preserves_wf`, `reset_wf`, `sail_model_init_wf`, `steps_safe`, `power_on_safe`;
     - halting: `step_halted`;
     - codec: `decode_encode`, `encode_injective`, `decode_eq_none_iff`;
     - illegal steps: `step_illegal`, `step_illegal_pc`, `step_illegal_of_opcode`;
     - frames: `execute_memory`, `execute_halted`, `execute_hlt`, `retire_sequential`, `step_memory`, `step_halts`, `step_sequential`.
   - The smoke test (`lean/smoke.sail`, `lean::smoke`) is removed.
   - Merging conflicts with later commits. On `just/model.just` `sources`, keep `model/instructions/*.sail` and drop `lean/*.sail`. On the `lint` fileset in `nix/checks.nix`, drop `../lean` and keep `../lem`.
   - Then:
     - wire the agent's new `lean::lint` into the root `lint` and the nix lint check;
     - update the README's `lean/` row and usage, which still mention the smoke test.
   - Known fragility: `decode_encode` slows to minutes if the instruction clauses are reordered (`rw [extract_op]` unifies against every `extractLsb` in the decode chain). The fix is an opcode table, plus a lemma `(encode i).extractLsb 15 11 = opcode i` used in place of that `rw`. The model split in `0d8d422` kept the clause order; check the proof time after merging.
4. **Specification** (user decided at the end of the session):
   - move the remaining framing prose out of the generator into the model as `$anchor` doc comments: title, subtitle, the introduction, the section titles (`document.py`: `TITLE`, `SUBTITLE`, `INTRODUCTION`, `SECTION_FILES`) and the two template sentences, as far as Sail allows;
   - use the asciidoctor-sail Asciidoctor plugin (Sail's own documentation toolchain, as in the RISC-V manual) instead of the hand-written AsciiDoc renderer; it is not in nixpkgs, so package the Ruby gem (e.g. `bundlerEnv`);
   - the user asked "what about LaTeX?": the recommendation is one AsciiDoc source rendered to HTML (asciidoctor) and PDF (asciidoctor-pdf), retiring the LaTeX path (`sail --latex`, `latex.py`, `doc/tara.tex`). Confirm with the user before deleting it.
   - Keep the generator as small as possible: it should only order and place what Sail generates.
5. **Sail Lem bug.** Sail 0.20.3 (and master as of 2026-10) generates `s.MEM` for a register named after a Lem keyword whose record field it escaped to `MEM'`. `nix/patches/sail-lem-register-keywords.patch` fixes it locally (19 lines in `src/lib/state.ml` and `src/sail_lem_backend/pretty_print_lem.ml`). Reporting it upstream (issue or PR on rems-project/sail) is a public action: ask the user first.
6. **Lem validation.** The user prefers proved properties to smoke tests, but no prover for Lem (Isabelle, HOL4) is in the shell; the Lem check is a typecheck plus the extracted Fibonacci run. Ask before adding a prover.
7. **Finish**: README pass (keep it minimal: layout, how to run, discrepancies, assumptions), `nix flake check -L` green, a whole-branch review, then offer to merge `tara-toolchain` into `main`.

## User preferences (follow these)

General:
- Ask before outward-facing actions (upstream issues, publishing). Commit in small, conventional commits and `git push` after every commit.
- One formatting width, 100 columns, enforced per language (black/ruff, `sail --fmt` with `sail_config.json`, clang-format, ocamlformat).
- Markdown for humans: never hard-wrap prose; enumerations as bullet lists. README: only layout, how to run, website-vs-Studio discrepancies and assumptions.
- No magic strings: named constants or enums. Prefer types over run-time validation.
- Tests: a real test suite (pytest) against a reference, parametrized over implementations; no goldens; no just-recipe test harnesses; test programs in assembly; helpers apart from tests; difflib diffs; Hypothesis for random programs.

just:
- Modules (`mod c "just/c.just"`) instead of prefixed recipe names; `[private]` intermediate steps with plain names; a `[default]` recipe per module; one command per recipe; doc comment on every recipe. See `.agents/skills/tara-just/SKILL.md`.

Python (see `.agents/skills/tara-python/SKILL.md`):
- Click CLIs with ParamType converters; uv/ruff/black/pyright strict; dependencies pinned `==` to the nixpkgs releases.
- Enums are classes with `= auto()` members (not the functional `StrEnum("X", "A B")` form, which the user rejected; a metaclass adding `auto()` was rejected because pyright cannot see its members). `tara.assembly.Named` keeps names as values.
- Keyword arguments for calls with several arguments; multi-field records are `@dataclass(frozen=True, kw_only=True)`.
- Typed models with `__str__` over string templates; domain models and generators in the `tara` library.

OCaml:
- A module per concept (`module Status = struct type t = ... end`), never bare top-level types; an `.mli` for every module except `main.ml`.
- Core and `Command_unix` (`Command.basic_or_error`, `Command.group`); ppx_jane derivers; `[%string]` interpolation (never `^`, never printf); `let%bind.Or_error`/`let%map.Or_error`; `{|...|}` raw strings; pipelines over nested application.
- No booleans as data; minimal mutation; 2D arrays (`Array.make_matrix`) over flattened indices; record patterns and construction annotated as `({ x } : Module.t)`; conversions in the type's module.
- All warnings on and errors (`-w +a-40-42-44 -warn-error +a`; each exception explained in `dune`).

C:
- CMake (Ninja) driven by just; strict C11; a broad GCC warning set as errors; generated and third-party headers as system headers.
- clang-tidy best-practice families as errors (`emulator/c/.clang-tidy`); a check may be disabled only with a written reason (the user questions every one). No `(void)` casts (cert-err33-c is off).
- Verb-first names for functions that act (`parse_options`, `load_program`), noun names for queries; check new names against Sail's headers (`rts.h` defines `load_image`).
- Explicit `if`/`else` for side-effecting conditions; conditional expressions only for pure value choices; `goto` cleanup for multi-resource functions (CERT MEM12-C).
- Tagged unions for sum types; return results by value rather than through out-parameters. Subcommands instead of mode flags.
- Sources in `emulator/c/src/`, configuration files beside it; headers next to their sources (no `include/`: the executable has no public API).

Rocq: the user briefly asked for ASCII-only Rocq and then reverted that; `<-` and other stdpp notations are fine.

## Known pitfalls

- pytest registers `--emulator` in `tests/conftest.py`; pass it as `--emulator=PATH` or pytest takes the value for a test path.
- Hypothesis has no Python 3.15 wheels and its own test suite fails on 3.15rc2, so Nix builds it with `doCheck = false` (`nix/default.nix`); the test dependencies are `[tool.tara] test-dependencies` in `pyproject.toml`, not a uv group.
- Sail's runtime C needs GNU C (`C_EXTENSIONS ON` on the model target); our sources are strict C11.
- clang-tidy reads GCC flags from the compile database: `.clang-tidy` passes `-Wno-unknown-warning-option`.
- Sail 0.20.3's LaTeX backend can print the wrong clause for a file whose first line is code; the generator checks every listing against the doc bundle (`ListingMismatch`). Doc comments on types are dropped by the bundle; `$anchor` comments carry such prose. Locations need the model given by a relative path.
- The OCaml backend is slow (about 15–45 µs a step); the suite's step limits are sized for it.
- `.superpowers/` (ignored) holds a progress ledger from the session; `.claude/worktrees/` (ignored) holds the agent worktrees.
