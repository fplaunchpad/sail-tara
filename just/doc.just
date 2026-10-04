# The specification typeset from the model.
import "settings.just"

set working-directory := ".."

# Where the listings, the document and the PDF are built.
out := build / "doc"

# Generate the LaTeX listings of the model and its assembly syntax.
[private]
[working-directory(out)]
generate: (build-dir "doc")
    sail --latex --latex-prefix tara "{{ justfile_directory() }}/model/syntax.sail"

# Take the listing style from Sail's example document.
[private]
preamble: (build-dir "doc")
    sed -n '/^\\usepackage/,/^\\def\\endsail/p' "{{ sail_dir }}/lib/sail.tex" \
        > "{{ out }}/sail-preamble.tex"

# Copy the document next to the generated listings.
[private]
source: (build-dir "doc")
    cp doc/tara.tex "{{ out }}/tara.tex"

# Typeset build/doc/tara.pdf; a warning, such as an unresolved link, is an error.
[default]
[working-directory(out)]
build: generate preamble source
    latexmk -pdf -interaction=nonstopmode -halt-on-error -Werror tara.tex
