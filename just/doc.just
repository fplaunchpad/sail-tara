# The specification from the Sail model, rendered as HTML and PDF from one AsciiDoc source.
import "settings.just"

set working-directory := ".."

out := build / "doc"

# Format the authored documentation configuration, stylesheet and PDF theme.
format:
    prettier --write doc/tara.css doc/tara-theme.yml doc/sail_config.json

# Check the authored documentation configuration, stylesheet and PDF theme formatting.
lint:
    prettier --check doc/tara.css doc/tara-theme.yml doc/sail_config.json

# Format a build-only copy of the Sail sources to fit the documentation code panels.
[private]
[script("bash", "-euo", "pipefail")]
documentation-sources: (build-dir "doc/model")
    shopt -s globstar
    for source in model/**/*.sail; do
        destination="{{ out }}/$source"
        mkdir -p "$(dirname "$destination")"
        sail --sail-config doc/sail_config.json --fmt --fmt-emit stdout "$source" > "$destination"
    done

# Bundle the formatted source text and documentation comments for the Sail Asciidoctor plugin.
[private]
[working-directory: out]
bundle: documentation-sources
    sail --doc --doc-embed plain --doc-bundle tara.json -o . model/syntax.sail

# Place the AsciiDoc layout beside the Sail bundle for standalone rendering.
[private]
specification: bundle
    cp doc/tara.adoc doc/tara.css doc/tara-theme.yml doc/cover.svg doc/sections.rb "{{ out }}/"

# Derive table metadata from the typed codecs and native assembly mapping.
[private]
metadata: (build-dir "doc")
    sail -plugin "$TARA_DOC_PLUGIN" --doc-tables --doc-tables-decode decode --doc-tables-encode encode --doc-tables-assembly assembly -o "{{ out }}/tables.json" model/syntax.sail

# Generate the format and opcode tables and the instruction sections from the metadata.
[private]
sections: metadata
    PYTHONPATH="{{ justfile_directory() }}/tools" "$TARA_PYTHON" -m tara.doc \
        "{{ out }}/tables.json" "{{ out }}"

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
build: specification sections fonts
    asciidoctor-pdf -r asciidoctor-sail -r "{{ out }}/sections.rb" --failure-level WARN -a pdf-theme="{{ out }}/tara-theme.yml" -a pdf-fontsdir="{{ out }}/fonts" -o "{{ out }}/tara.pdf" "{{ out }}/tara.adoc"

# Render the same source to HTML; a warning is an error.
[private]
render-html: specification sections fonts
    asciidoctor -r asciidoctor-sail -r "{{ out }}/sections.rb" --failure-level WARN -a stylesheet=tara.css -o "{{ out }}/tara.html" "{{ out }}/tara.adoc"

# Format the generated HTML for a stable, readable offline document.
html: render-html
    prettier --write "{{ out }}/tara.html"
