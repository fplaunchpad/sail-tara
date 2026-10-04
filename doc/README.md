# Specification

The specification is generated from the Sail model. `main.adoc` lays out the chapters; the prose and the listings come from the model's documentation comments and sources, through the [asciidoctor-sail](https://github.com/Alasdair/asciidoctor-sail) plugin. The Sail plugin in `tools/sail-doc` reads the instructions' encodings, syntax and clauses from the model, and `tools/tara/doc.py` turns them into the format table, the opcode (or encoding) table and a section per instruction.

From the repository root inside `nix develop` (or direnv):

```sh
just doc            # build/doc/tara.pdf
just doc html       # build/doc/tara.html
just doc lint
just test -k doc    # the specification's tests
```

- `styles.css` and `theme.yml` style the HTML and the PDF, with the fonts from `nix/doc-fonts.nix`.
- `sections.rb` numbers the sections and aligns the numbers in the table of contents.
- `sail_config.json` sets the width of the listings.

## What the generated parts assume

The tests check these on TARA and on smaller instruction sets in `tests/instruction_sets/`, among them a 32-bit one laid out like RISC-V.

The model:

- The instructions are the constructors of the union that the mapping `assembly` maps to text, one instruction per constructor. A constructor that stands for several instructions, such as one with an operation argument, is documented as one.
- Decoding is a function `decode`, not a mapping (the plugin's `--doc-tables-decode` and `--doc-tables-assembly` name other functions). Each clause but the last returns `Some(C(...))` for its own constructor, without a guard; the last is `decode(_) = None()`, which is needed even when every encoding is assigned, because Sail's completeness check otherwise turns the last clause's fixed bits into a wildcard.
- A decode pattern concatenates fixed bits, names and wildcards (or is one of them). Fixed bits may sit anywhere and may be named with `as`, as in `(0b000 as funct3)`. Every encoding has the same width.
- An `assembly` clause is two-way and unguarded, `C(names) <-> text`, where the text concatenates strings, mappings of one operand (shown by the operand's name in `decode`) and mappings from unit, such as separators (inlined). The first clause for an instruction gives its syntax.
- An instruction's section shows each function or mapping clause that takes the instruction apart (`f(C(...))`), builds it as decode does, or has it on either side of a mapping, in source order, and the comments of those that have one. A clause that takes the instruction with other arguments is not found.
- The instruction sections follow the files that define instructions: their documented `$anchor`s and instructions, in source order.

The generator:

- The opcode table lists every value of a single leading opcode field when such a field tells the instructions apart; otherwise the table lists each instruction's encoding.
- A format is a layout of field names and widths; unnamed fixed bits are labelled `opcode` and ignored bits `-`. Formats are numbered in the order of their first encodings.
- The format table has a column per bit, which suits words of up to 32 bits.
- An instruction's mnemonic is its constructor's name, and its heading is at level 4 (`--section-level`), under the headings of the anchors before it.

By hand:

- `main.adoc` lists the definitions outside the instruction sections: the machine state, the instruction set's introduction, execution and assembly syntax. A new register, type or helper needs its two lines there.
