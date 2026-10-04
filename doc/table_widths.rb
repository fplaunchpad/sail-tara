# frozen_string_literal: true

# asciidoctor-pdf measures a table cell's text at the document's base font size, not the table's,
# so an autowidth table whose cells hold code in em sizes gets columns too wide for its text.
# Measure each cell at its own font size instead.
class Prawn::Table::Cell::Text
  alias_method :base_size_styled_width_of, :styled_width_of

  def styled_width_of(text)
    size = @text_options[:size]
    return base_size_styled_width_of(text) unless size

    base_size = @pdf.font_size
    @pdf.font_size = size
    base_size_styled_width_of(text)
  ensure
    @pdf.font_size = base_size if base_size
  end
end
