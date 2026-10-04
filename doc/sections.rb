# frozen_string_literal: true

require 'asciidoctor/extensions'

module TaraSectionNumberColumns
  def number_columns
    digit_counts = sectnum('.', false).split('.').map(&:length)
    document.find_by(context: :section)
      .select do |section|
        section.numbered && section.level == level &&
          section.sectnum('.', false).split('.').map(&:length) == digit_counts
      end
      .map { |section| section.sectnum('.', false).split('.') }
      .transpose
  end
end

# Use the renderer's inline layout for number columns; fonts stay in the theme.
module TaraPdfSectionTitles
  include TaraSectionNumberColumns

  def numbered_title(opts = {})
    result = super
    return result unless numbered && !caption && level <= document.attr('sectnumlevels', 3).to_i

    if opts[:formal]
      return "§#{result}" unless level == 1

      return "<span class=\"chapter-number\">#{numeral}</span>  #{title}"
    end

    number = sectnum('.', false).split('.').zip(number_columns).map do |part, column|
      width = column.map { |value| converter.width_of(value) }.max
      "<span style=\"width: #{width}pt; text-align: right\">#{part}</span>."
    end.join
    "#{number} #{title}"
  end
end

module TaraHtmlSectionNumbers
  include TaraSectionNumberColumns

  def sectnum(delimiter = '.', append = nil)
    number = super
    return number unless delimiter == '.' && append.nil?

    case converter.number_context
    when :heading
      level == 1 ? "<span class=\"chapter-number\">#{numeral}</span>" : "§#{number}"
    when :toc
      number.chomp('.').split('.').zip(number_columns).map do |part, column|
        width = column.map(&:length).max
        "<span class=\"section-number\" style=\"width: #{width}ch\">#{part}</span>."
      end.join
    else
      number
    end
  end
end

module TaraHtmlLayout
  attr_reader :number_context

  def convert_section(node)
    previous_context = @number_context
    @number_context = :heading
    super
  ensure
    @number_context = previous_context
  end

  def convert_outline(node, opts = {})
    previous_context = @number_context
    @number_context = :toc
    super
  ensure
    @number_context = previous_context
  end
end

class TaraDocLayout < Asciidoctor::Extensions::TreeProcessor
  def process(document)
    pdf = document.backend == 'pdf'
    document.converter.extend TaraHtmlLayout unless pdf
    document.find_by(context: :section).each do |section|
      section.extend(pdf ? TaraPdfSectionTitles : TaraHtmlSectionNumbers)
    end

    document.find_by(context: :listing).each do |listing|
      listing.set_option 'unbreakable'
    end

    document
  end
end

Asciidoctor::Extensions.register do
  tree_processor TaraDocLayout
end
