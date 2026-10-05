# Specification

The specification is built from the Sail model. Its prose and listings come from the model's doc comments and sources, through [asciidoctor-sail](https://github.com/Alasdair/asciidoctor-sail). The instruction tables and sections come from `tools/sail-doc`, which reads the instructions from the model, and `tools/tara/doc.py`, which writes them as AsciiDoc.

## Usage

Inside `nix develop` (or direnv), from the repository root:

```sh
just doc            # build/doc/tara.pdf
just doc html       # build/doc/tara.html
just doc lint
just test -k doc    # the specification's tests
```

## Layout

| File | Contents |
|---|---|
| `main.adoc` | The chapters: what to include from the model, in order |
| `styles.css`, `theme.yml` | HTML and PDF styles; the fonts come from `nix/doc-fonts.nix` |
| `sections.rb` | Numbers the sections and aligns the numbers in the table of contents |
| `table_widths.rb` | Fixes asciidoctor-pdf measuring table cells at the body font size, so tables fit their contents |
| `sail_config.json` | The width of the listings |

## What the model must look like

The tests check these on TARA and on the instruction sets in `tests/instruction_sets/`, one of them laid out like RISC-V.

- **Encoding:** a mapping `encdec` from the instruction union to words.
  - Each clause is one instruction: a constructor applied to operand names and constants, so one constructor (such as `RTYPE(rs2, rs1, rd, ADD)`) can stand for several instructions.
  - The right side concatenates fixed bits, operands, and mappings of one operand or of constants only, which are ignored bits (`ignored(11)`).
  - A type that annotates fixed bits names them (`0b00000 : opcode`); unnamed fixed bits have a blank label.
  - A guard is shown as the encoding's condition. Unguarded clauses must differ in their fixed bits.
- **Syntax:** the first `assembly` clause that applies to the instruction. Its text concatenates strings and mappings: a mapping of an operand shows the operand's name, and a mapping of a constant or unit (a mnemonic table, a separator) is inlined.
- **Execution:** the first `execute` clause that applies, a statement a line, in reference-card notation.
  - Operators are kept, bit literals become numbers, and `0 @ x` becomes `zext(x)`.
  - Sail's library has built-in notations (`signed` is `sext`, and so on). The model gives its own functions, registers and constants one with an attribute, such as `$[notation "R[{0}]"]`.
  - Anything else is a call, and a construct the notation does not cover (such as `match`) is shown as its source.
- **Sections:** one per constructor, in source order, among the documented `$anchor`s of the files that define instructions. Each shows every function or mapping clause that takes the constructor apart, with its comment. asciidoctor-sail picks the first clause that matches, so a clause hidden by an earlier one of the same function is an error.
- **Names:** `--doc-tables-encdec`, `--doc-tables-assembly` and `--doc-tables-execute` select other mappings and functions than `encdec`, `assembly` and `execute`.

## What the generator does

- **Opcode table:** a row per value of the opcode, when a single leading fixed field tells the instructions apart and no encoding is guarded. Otherwise an encoding table, a row per instruction, with a condition column if any encoding is guarded.
- **Formats:** a format is a layout of field names and widths, numbered in the order of its first encoding. The format table has a column per run of bits between field boundaries.
- **Mnemonics** are the first word of the syntax. Constructor headings are at level 4 (`--section-level`).

## By hand

`main.adoc` lists the definitions outside the instruction sections: the machine state, the introduction to the instruction set, execution and the assembly syntax. A new register, type or helper needs its two lines there.
