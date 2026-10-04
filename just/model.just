# The Sail model: typecheck and formatting.
import "settings.just"

set working-directory := ".."

# Sail sources, formatted and checked together.
sources := "model/*.sail model/instructions/*.sail emulator/*.sail"
# Formatter settings; line_width is also the limit for every Sail line.
config := "sail_config.json"
width := shell('jq .fmt.line_width "$1"', config)

# Typecheck the model and the emulators' host interface.
[default]
check:
    sail --just-check emulator/host.sail

# Format the Sail sources in place.
format:
    sail --sail-config {{ config }} --fmt {{ sources }}

# Check that the Sail sources are formatted.
[private]
format-check:
    status=0; for file in {{ sources }}; do sail --sail-config {{ config }} --fmt --fmt-emit stdout "$file" | diff -u --label "$file" --label "$file (formatted)" "$file" - || status=1; done; exit "$status"

# Check that no Sail line is longer than the formatter's line width.
[private]
width-check:
    LC_ALL=C awk -v width={{ width }} 'length > width { print FILENAME ":" FNR ": " length " columns"; status = 1 } END { exit status }' {{ sources }}

# Check the formatting and line width of the Sail sources.
lint: format-check width-check
