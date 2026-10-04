# Specification

The specification is generated from the Sail model. `main.adoc` lays out the chapters; the prose and the listings come from the model's documentation comments and sources, through the [asciidoctor-sail](https://github.com/Alasdair/asciidoctor-sail) plugin. The Sail plugin in `tools/sail-doc` derives the instruction metadata from the model's `decode` function and `assembly` mapping, and `tools/tara/doc.py` turns it into the format table, the opcode table and a section per instruction, grouped by the file in `model/instructions/` that defines it.

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
