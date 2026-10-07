# Specification

`just doc` builds `build/doc/tara.pdf`; `just doc html` builds `build/doc/tara.html`.
Both use the same generated AsciiDoc and SVG assets, with local fonts for offline reading.
Run the commands inside `nix develop` or direnv. `just test -k doc` checks the generator.

The Sail model is normative. Instruction entries present its semantics as a readable reference:
assembly syntax, proportional encoding diagrams, field meanings, ordered operations,
architectural notes and related instructions. A notation guide explains widths, sequencing and
the shared retirement steps once. The helper appendix gives exact
definitions without repeating dependency lists or Sail source listings.

The opcode and encoding tables and instruction sections use the same symbolic operations.
Fixed-width arithmetic wraps implicitly; `s(x)` retains signed interpretation, slices retain
explicit truncation, and `zextN` and `sextN` retain extension widths. Memory calls use the model's
notation, branches use compact blocks, and statement order is preserved. The helper appendix and
shared retirement sequence use this notation too.

## Generation

`tools/sail-doc` reads Sail's typed AST and emits schema version 2 metadata. It derives encodings,
constructor variants, assembly templates, expression widths, operation order, guards and helper
calls. Validation inputs are interpreted by the pinned Sail interpreter; neither Python nor a
second ISA implementation computes their results. They remain in metadata for checks and are
not rendered in the reference. `tools/tara/doc.py` renders the metadata.

Prose remains beside the semantics in `model/`: the instruction's execute doc comment supplies
its overview, and an `instruction_doc` attribute on each encoding supplies editorial metadata.
The generator does not infer architectural intent from code. It rejects unsupported operation
constructs, invalid annotations, missing coverage and unresolved links instead of guessing.

## Authoring an instruction

Keep the union constructor, `encdec`, `execute` and `assembly` clauses as usual. Add this attribute
immediately before the encoding clause (see `model/instructions/arithmetic.sail`):

```sail
$[instruction_doc {
    title = "Add immediate",
    operands = [
        { name = rd, interpretation = "register", access = read_write,
          description = "Destination register" },
        { name = imm, interpretation = signed, access = value,
          description = "Immediate value" },
    ],
    examples = [{
        title = "Add a negative immediate",
        operands = [{ name = rd, value = "0b011" }, { name = imm, value = "0xFF" }],
        before = [{ "register" = GPR, index = 3, value = "0x0000" }],
        watch = [R3],
    }],
    related = [ADD, SUB],
}]
```

Every encoding operand must have exactly one description. Interpretations are `register`,
`signed` or `unsigned`; access is `read`, `write`, `read_write` or `value`. `unit` is optional.
Ranges and bit positions are derived from field widths. Notes have a `category` of `usage`,
`architecture` or `assumption`, and `text`. Use `assumption` for behavior the hardware description
does not specify. Related names must identify one instruction unambiguously.

The `examples` annotations provide validation inputs, never expected results. They are not displayed
in instruction entries. Operands and state values are Sail literals with
the correct types and widths; expressions and calls are rejected. `before` overrides the example
context's initial state. `arguments` optionally overrides the runner's input arguments. `watch`
keeps an unchanged observed value in the result table. Changed values and PC are retained.
Unspecified register state starts at zero (false for booleans); each example has fresh state and
a 100,000 interpreter-step limit. TARA examples run decoded instructions without fetching them.

`doc_examples` on the `execute` value declaration selects the runner, default arguments, initial
state, observation labels and completeness policy (see `model/tara.sail`). With `complete = true`,
every encoding needs an overview, annotated operands and an evaluated example, and every operation
helper must resolve. Quote reserved attribute keys such as `"register"`.

Vector observation labels substitute `{index}` for a decimal index or `{index:03X}` for a
three-digit hexadecimal index, as in TARA's `M[0x{index:03X}]` memory labels.

One constructor can represent several encodings, as `RTYPE` does in the RISC-V-like fixture.
Each gets its own entry and SVG. Single-variant anchors retain `insn-CONSTRUCTOR`; multiple variants
use `insn-CONSTRUCTOR-MNEMONIC`. Set an optional `id` in `instruction_doc` when variants need an
explicit stable identifier. Encoding guards on both sides are preserved, and guarded execute
clauses retain their order and fallback.

## Helpers and operation notation

Add `$[helper_doc { title = "Read word" }]` to a helper to include it even if no instruction calls
it. Its doc comment supplies explanatory prose. Other functions in the model's source directory
are included recursively when reachable from instruction operations or documented helpers.
Functions show typed operations; mappings show their encode/print and decode/parse rules, including
guards. New helpers do not require edits to the chapter layout.

`$[notation "R[{0}]"]` supplies display names for architectural registers or accessors. Extraction
still retains call identity and typed widths. Built-in rendering distinguishes `s(x)`, an
integer interpretation, from `sextN(x)`, a wider bit vector. The primitive appendix defines
both, plus wrapping, zero extension, bit selection, concatenation and logical shifts. Primitive
contracts live in `tools/tara/doc_reference.py` and follow the pinned Sail library.

The structured operation representation currently supports literals, identifiers, calls, infix
operators, slices, conditional expressions, named local bindings, assignments, blocks and branches.
Other constructs fail at their source location. Add an explicit typed IR case and renderer before
using a new construct; do not fall back to opaque Sail text in the readable reference. Helpers with
multiple function patterns currently require that additional support.

## Layout and checks

| File | Responsibility |
|---|---|
| `main.adoc` | Chapter order and machine-state explanations |
| `styles.css`, `theme.yml` | HTML and PDF presentation |
| `sections.rb` | Section numbering and listing pagination |
| `table_widths.rb` | PDF table measurement |
| `sail_config.json` | Bundled source formatting |
| `nix/doc-fonts.nix` | Local fonts |

Generated outputs are `tables.json`, `formats.adoc`, `opcodes.adoc`, `notation.adoc`,
`instructions.adoc`, `helpers.adoc` and `encodings/*.svg`. Do not edit them.
New architectural state still belongs in `main.adoc`'s machine-state chapter.

The tests compare evaluated examples with TARA Studio's assembler and the corrected independent
reference CPU, check exact SVG field proportions, all cross-reference targets, readable-operation
coverage, metadata errors, and generic 4-, 12- and 32-bit instruction sets. There are no golden files.

```sh
just model lint
just sail-doc lint
just python lint
just doc lint
just test -k doc
```
