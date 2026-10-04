# The specification typeset from the model.
import "settings.just"

set working-directory := ".."

# Generate the LaTeX listings of the model and its assembly syntax.
[private]
generate: (build-dir "doc")
    cd "{{ build }}/doc" && sail --latex --latex-prefix tara "{{ justfile_directory() }}/model/syntax.sail"

# Take the listing style from Sail's example document.
[private]
preamble: (build-dir "doc")
    sed -n '/^\\usepackage/,/^\\def\\endsail/p' "{{ sail_dir }}/lib/sail.tex" > "{{ build }}/doc/sail-preamble.tex"

# Copy the document next to the generated listings.
[private]
source: (build-dir "doc")
    cp doc/tara.tex "{{ build }}/doc/tara.tex"

# Typeset build/doc/tara.pdf.
[default]
build: generate preamble source
    cd "{{ build }}/doc" && latexmk -pdf -interaction=nonstopmode -halt-on-error tara.tex
