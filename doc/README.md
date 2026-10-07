# Specification

`just doc` builds `build/doc/tara.pdf`; `just doc html` builds `build/doc/tara.html`.
Run inside `nix develop` or direnv. Both use the same generated AsciiDoc, SVG diagrams and local
fonts. The Sail model is normative; the reference presents its encodings, assembly syntax,
operand descriptions, ordered symbolic operations and architectural notes.

## Authoring

Use Sail's native `/*! ... */` documentation comments. An instruction's comment belongs above its
`execute` clause:

```sail
/*!
@brief Add immediate

Adds the immediate, sign-extended, to `rd`.

@param rd Destination register, read and written.
@param imm Signed immediate.
@see ADD, SUB
 */
function clause execute(ADDI(rd, imm)) = {
    X(rd) = X(rd) + signed(imm)
}
```

| Marker | Meaning |
|---|---|
| `@brief title` | Instruction or helper title |
| `@param name description` | Ordinary description of an encoding operand |
| `@note text` | Architectural detail |
| `@usage text` | Usage constraint |
| `@assumption text` | Behavior assumed where the hardware description is silent |
| `@see ADD, SUB` | Related instruction names, separated by commas or whitespace |
| `@notation M[{0}][15:0]` | Literal display template for a register or accessor |
| `@id stable-name` | Optional stable instruction-variant identifier |
| `@anchor chapter_name` | Named chapter fragment; its following lines contain AsciiDoc |

Markers begin a line, optionally indented. Continuation lines belong to the preceding marker.
A blank line after `@brief` starts the instruction or helper's overview; prose before markers is
also an overview. Paragraphs and AsciiDoc markup are preserved. In a chapter comment, each
`@anchor` starts another fragment. Group adjacent chapter fragments into one comment: Sail permits
only one doc comment per definition.

The parser rejects unknown or malformed markers, repeated singleton markers, duplicate parameters
or anchors, missing encoding operands and unresolved related instructions. Production builds use
`--doc-tables-complete` to require documentation for every encoding. Generic models can omit it.
An encoding-specific comment above an `encdec` clause replaces the matching execute comment in
full; use it for constructor variants. Its `@param` names must match that encoding's field names.

Single variants keep `insn-CONSTRUCTOR` anchors; multiple variants use
`insn-CONSTRUCTOR-MNEMONIC`. Use `@id` when a variant needs an explicit stable identifier.
Guards on both mapping sides and the order of guarded execution clauses are preserved.

## Helpers and notation

A helper's `@brief` includes it in the appendix even if no instruction calls it. Put the comment
above its definition or its `val` declaration. Other model helpers are discovered recursively
through their callers; adding one requires no chapter-layout changes. Function definitions become
typed symbolic operations, and mappings show encode/print and decode/parse rules with their guards.

`@notation` changes only display text: call identity and typed widths remain available to the
generator. Templates substitute `{0}`, `{1}`, etc. for arguments. Instructions and opcode tables
use the same notation: `R[...]`, `M[...][15:0]`, square-bracket slices, `s(x)`, `sextN` and `zextN`.
The appendix defines these operations, including the precise `sign_extend_16` contract.
Primitive contracts in `tools/tara/doc_reference.py` follow the pinned Sail library.

Unsupported operation constructs fail at their source location. Add a typed operation case and
renderer before using a new construct. Helpers with multiple function patterns currently need
that additional support.

## Generation and validation

`tools/sail-doc` reads Sail's typed AST and parses comments with Angstrom. Schema version 3 contains
encodings, syntax, expression widths, guards, operations, helper dependencies and comment fragments.
Operands contain only names and descriptions. `tools/tara/doc.py` generates ordinary AsciiDoc
includes, so no Sail documentation bundle or Asciidoctor Sail extension is needed for rendering.

Validation inputs live separately in `tests/fixtures/doc_examples.json`. The optional
`--doc-tables-examples FILE` evaluates them with the pinned Sail interpreter; normal documentation
builds neither load them nor render examples. The fixture names a runner, initial state, observed
registers and instruction syntax templates with literal operands. It contains inputs, not expected
outputs. Tests compare interpreted results with TARA Studio's assembler and the corrected reference
CPU, including boundary, aliasing and memory cases.

Generated outputs are `tables.json`, `formats.adoc`, `opcodes.adoc`, `notation.adoc`,
`instructions.adoc`, `helpers.adoc`, `comments/{anchor,register,let}/*.adoc` and
`encodings/*.svg`. Do not edit them. `main.adoc` owns chapter order and selects machine-state
fragments; `styles.css` and `theme.yml` own presentation, with `sections.rb` and `table_widths.rb`
handling section numbering and PDF layout.

```sh
just model lint
just sail-doc build
just sail-doc lint
just python lint
just doc lint
just test -k doc
```
