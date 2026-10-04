# Generate the LaTeX listings of the model and its assembly syntax.
[group('doc')]
doc-gen: (build-dir "doc")
    cd "{{ build }}/doc" && sail --latex --latex-prefix tara "{{ justfile_directory() }}/model/syntax.sail"

# Take the listing style from Sail's example document.
[group('doc')]
doc-preamble: (build-dir "doc")
    sed -n '/^\\usepackage/,/^\\def\\endsail/p' "{{ sail_dir }}/lib/sail.tex" > "{{ build }}/doc/sail-preamble.tex"

# Copy the document next to the generated listings.
[group('doc')]
doc-src: (build-dir "doc")
    cp doc/tara.tex "{{ build }}/doc/tara.tex"

# Typeset build/doc/tara.pdf.
[group('doc')]
doc-pdf: doc-gen doc-preamble doc-src
    cd "{{ build }}/doc" && latexmk -pdf -interaction=nonstopmode -halt-on-error tara.tex

# Build the PDF specification, build/doc/tara.pdf.
[group('doc')]
doc: doc-pdf
