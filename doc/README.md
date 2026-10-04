# Specification

The specification is generated from the Sail model. `main.adoc` lays out the chapters; the prose and the listings come from the model's documentation comments and sources, through the [asciidoctor-sail](https://github.com/Alasdair/asciidoctor-sail) plugin. The Sail plugin in `tools/sail-doc` reads the instructions' encodings, syntax, execution and clauses from the model, and `tools/tara/doc.py` turns them into the format table, the opcode (or encoding) table and a section per instruction constructor.

From the repository root inside `nix develop` (or direnv):

```sh
just doc            # build/doc/tara.pdf
just doc html       # build/doc/tara.html
just doc lint
just test -k doc    # the specification's tests
```

- `styles.css` and `theme.yml` style the HTML and the PDF, with the fonts from `nix/doc-fonts.nix`.
- `sections.rb` numbers the sections and aligns the numbers in the table of contents.
- `table_widths.rb` makes the PDF measure a table cell at the table's font size, so a table sized to its contents (autowidth) is as wide as its text.
- `sail_config.json` sets the width of the listings.

## What the generated parts assume

The tests check these on TARA and on smaller instruction sets in `tests/instruction_sets/`, among them a 32-bit one laid out like RISC-V.

The model:

- Encoding is a mapping `encdec` from the instruction union to words (the plugin's `--doc-tables-encdec`, `--doc-tables-assembly` and `--doc-tables-execute` name other mappings and functions). Each of its clauses is one instruction: a constructor applied to operand names and constants, such as an enum member that selects an operation, so one constructor can stand for several instructions.
- The right side of an `encdec` clause concatenates fixed bits, operands and mappings applied to one operand or only to constants (ignored bits, such as `ignored(11)`). A type synonym that annotates fixed bits names them, as in `0b00000 : opcode`. A guard on a clause is shown as its encoding's condition. Unguarded clauses must differ in their fixed bits.
- An instruction's syntax is the first `assembly` clause that applies to it, `C(names and constants) <-> text`, where the text concatenates strings and mappings. A mapping applied to an operand shows the operand's name in `encdec`; one applied to a constant or unit, such as a mnemonic table or a separator, is inlined.
- An instruction's execution is the body of the first `execute` clause that applies to it, a statement a line, so a clause shared by several instructions shows the same body for each. It is written in a reference card's notation: operators as in the source, bit literals as numbers, `0 @ x` as `zext(x)`, Sail's library (`signed`, `unsigned`, shifts, `get_slice_int`) by built-in notations, and the model's own functions, registers and constants by the attribute `$[notation "R[{0}]"]`, whose `{0}`, `{1}` stand for the arguments. Anything else is written as a call, and a construct the notation does not cover (such as `match`) as its source.
- A constructor's section shows each function or mapping clause that takes the constructor apart (`f(C(...))`, or either side of a mapping), in source order, and the comments of those that have one. asciidoctor-sail finds a clause by its constructor and its enum and bit-literal arguments, taking the first that matches, so a clause that an earlier one of the same function hides is an error.
- The sections follow the files that define instructions: their documented `$anchor`s and constructors, in source order.

The generator:

- The opcode table lists every value of a single leading opcode field when such a field tells the instructions apart and no encoding is guarded; otherwise the table lists each instruction's encoding, with a condition column if any is guarded.
- A format is a layout of field names and widths; unnamed fixed bits have a blank label and ignored bits `-`. Formats are numbered in the order of their first encodings.
- The format table has a column per run of bits between field boundaries, headed by its first and last bit. The opcode and encoding tables are sized to their contents.
- An instruction's mnemonic is the first word of its syntax, and a constructor's heading is at level 4 (`--section-level`), under the headings of the anchors before it.

By hand:

- `main.adoc` lists the definitions outside the instruction sections: the machine state, the instruction set's introduction, execution and assembly syntax. A new register, type or helper needs its two lines there.
