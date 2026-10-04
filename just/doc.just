# The specification typeset from the model.
import "settings.just"

set working-directory := ".."

# Where Sail's output, the document and its PDF and HTML are built.
out := build / "doc"

# Sail's documentation of the model: its definitions, with their comments, their text and their
# places in the files. Sail records the places only for a file given by a path from here.
[private]
bundle: (build-dir "doc")
    sail --doc --doc-embed plain --doc-embed-with-location --doc-bundle tara.json -o "{{ out }}" model/syntax.sail

# Sail's LaTeX listings of the definitions of the model.
[private]
[working-directory(out)]
listings: (build-dir "doc")
    sail --latex --latex-prefix tara "{{ justfile_directory() }}/model/syntax.sail"

# Take the listing style from Sail's example document.
[private]
preamble: (build-dir "doc")
    sed -n '/^\\usepackage/,/^\\def\\endsail/p' "{{ sail_dir }}/lib/sail.tex" \
        > "{{ out }}/sail-preamble.tex"

# Write the document from the documentation: its sections in LaTeX, and all of it in AsciiDoc.
[private]
specification: bundle listings
    PYTHONPATH="{{ justfile_directory() }}/tools" "$TARA_PYTHON" -m tara.specification \
        --bundle "{{ out }}/tara.json" --commands "{{ out }}/sail_latex/commands.tex" \
        --latex "{{ out }}/specification.tex" --asciidoc "{{ out }}/tara.adoc"

# Copy the frame of the document next to its sections.
[private]
frame: (build-dir "doc")
    cp doc/tara.tex "{{ out }}/tara.tex"

# Typeset build/doc/tara.pdf; a warning, such as an unresolved link, is an error.
[default]
[working-directory(out)]
build: specification preamble frame
    latexmk -pdf -interaction=nonstopmode -halt-on-error -Werror tara.tex

# Render build/doc/tara.html from the AsciiDoc; a warning is an error.
[working-directory(out)]
html: specification
    asciidoctor --failure-level=WARN -o tara.html tara.adoc
