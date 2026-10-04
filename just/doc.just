# The specification from the Sail model, rendered as HTML and PDF from one AsciiDoc source.
import "settings.just"

set working-directory := ".."

out := build / "doc"

# Format the stylesheet, the PDF theme and the listing width.
format:
    prettier --write doc/styles.css doc/theme.yml doc/sail_config.json

# Check the formatting of the stylesheet, the PDF theme and the listing width.
lint:
    prettier --check doc/styles.css doc/theme.yml doc/sail_config.json

# Format a copy of the Sail sources to the width of the listings.
[private]
[script("bash", "-euo", "pipefail")]
documentation-sources: (build-dir "doc/model")
    shopt -s globstar
    for source in model/**/*.sail; do
        destination="{{ out }}/$source"
        mkdir -p "$(dirname "$destination")"
        sail --sail-config doc/sail_config.json --fmt --fmt-emit stdout "$source" > "$destination"
    done

# Bundle the formatted sources and their documentation comments for the Asciidoctor plugin.
[private]
[working-directory(out)]
bundle: documentation-sources
    sail --doc --doc-embed plain --doc-bundle tara.json -o . model/syntax.sail

# Place the AsciiDoc layout and its styles beside the bundle.
[private]
specification: bundle
    cp doc/main.adoc doc/styles.css doc/theme.yml doc/cover.svg doc/sections.rb \
        doc/table_widths.rb "{{ out }}/"

# Derive the instruction metadata from the model's encdec and assembly mappings and execute.
[private]
metadata: (build-dir "doc")
    sail -plugin "$TARA_DOC_PLUGIN" --doc-tables -o "{{ out }}/tables.json" model/syntax.sail

# Generate the format and opcode tables and the instruction sections from the metadata.
[private]
sections: metadata
    PYTHONPATH="{{ justfile_directory() }}/tools" "$TARA_PYTHON" -m tara.doc \
        "{{ out }}/tables.json" "{{ out }}"

# Prepare a writable font directory for repeated documentation builds.
[private]
font-directory: (build-dir "doc")
    install -d -m755 "{{ out }}/fonts"

# Include the text and code fonts, for offline HTML and a standalone PDF.
[private]
fonts: font-directory
    install -m644 -t "{{ out }}/fonts" "$TARA_DOC_FONTS"/*

# Render the PDF, build/doc/tara.pdf; a warning is an error.
[default]
build: specification sections fonts
    asciidoctor-pdf -r asciidoctor-sail -r "{{ out }}/sections.rb" \
        -r "{{ out }}/table_widths.rb" --failure-level WARN \
        -a pdf-theme="{{ out }}/theme.yml" -a pdf-fontsdir="{{ out }}/fonts" \
        -o "{{ out }}/tara.pdf" "{{ out }}/main.adoc"

# Render the HTML; a warning is an error.
[private]
render-html: specification sections fonts
    asciidoctor -r asciidoctor-sail -r "{{ out }}/sections.rb" --failure-level WARN \
        -a stylesheet=styles.css -o "{{ out }}/tara.html" "{{ out }}/main.adoc"

# Render the HTML, build/doc/tara.html, formatted for reading.
html: render-html
    prettier --write "{{ out }}/tara.html"
