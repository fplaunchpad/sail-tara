# The specification from the Sail model, rendered as HTML and PDF from one AsciiDoc source.
import "settings.just"

set working-directory := ".."

out := build / "doc"

# Format the authored stylesheet and PDF theme.
format:
    prettier --write doc/tara.css doc/tara-theme.yml

# Check the authored stylesheet and PDF theme formatting.
lint:
    prettier --check doc/tara.css doc/tara-theme.yml

# Bundle the model's source text and documentation comments for the Sail Asciidoctor plugin.
[private]
bundle: (build-dir "doc")
    sail --doc --doc-embed plain --doc-bundle tara.json -o "{{ out }}" model/syntax.sail

# Place the AsciiDoc layout beside the Sail bundle for standalone rendering.
[private]
specification: bundle
    cp doc/tara.adoc doc/tara.css doc/tara-theme.yml "{{ out }}/"

# Derive table metadata from the typed codecs and native assembly mapping.
[private]
metadata: (build-dir "doc")
    sail -plugin "$TARA_DOC_PLUGIN" --doc-tables --doc-tables-decode decode --doc-tables-encode encode --doc-tables-assembly assembly_syntax -o "{{ out }}/tables.json" model/syntax.sail

# Render the opcode and format summary tables from normalized metadata.
[private]
tables: metadata
    PYTHONPATH="{{ justfile_directory() }}/tools" "$TARA_PYTHON" -m tara.doc_tables --metadata "{{ out }}/tables.json" --out "{{ out }}"

# Prepare a writable font directory for repeated documentation builds.
[private]
font-directory: (build-dir "doc")
    install -d -m755 "{{ out }}/fonts"

# Include the text and code fonts for offline HTML and standalone PDF rendering.
[private]
fonts: font-directory
    install -m644 -t "{{ out }}/fonts" "$TARA_DOC_FONTS"/*

# Render the single AsciiDoc source to PDF; a warning is an error.
[default]
build: specification tables fonts
    asciidoctor-pdf -r asciidoctor-sail --failure-level WARN -a pdf-theme="{{ out }}/tara-theme.yml" -a pdf-fontsdir="{{ out }}/fonts" -o "{{ out }}/tara.pdf" "{{ out }}/tara.adoc"

# Render the same source to HTML; a warning is an error.
[private]
render-html: specification tables fonts
    asciidoctor -r asciidoctor-sail --failure-level WARN -a stylesheet=tara.css -o "{{ out }}/tara.html" "{{ out }}/tara.adoc"

# Format the generated HTML for a stable, readable offline document.
html: render-html
    prettier --write "{{ out }}/tara.html"
