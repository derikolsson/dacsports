module ReportsHelper
  # "▲ 12% vs 340 previous period" beneath a headline figure. Nothing when there's no
  # previous period to compare against.
  def period_change(current, previous)
    return if previous.nil?

    if previous.zero?
      change = current.zero? ? "No change" : "New"
      css = current.zero? ? "text-muted" : "text-success"
    else
      pct = ((current - previous) * 100.0 / previous).round
      change = pct.zero? ? "No change" : "#{pct.positive? ? "▲" : "▼"} #{pct.abs}%"
      css = if pct.positive? then "text-success" elsif pct.negative? then "text-danger" else "text-muted" end
    end

    tag.small(class: "d-block #{css}") do
      safe_join([ change, tag.span(" vs #{number_with_delimiter(previous)} previous period", class: "text-muted") ])
    end
  end

  # "🇺🇸 United States" for an ISO country code: its flag from regional indicator letters,
  # then its everyday name, or the code itself for one the countries gem doesn't know.
  def country_label(code)
    return code unless code.to_s.match?(/\A[A-Z]{2}\z/)

    flag = code.chars.map { |char| (char.ord + 0x1F1A5).chr(Encoding::UTF_8) }.join
    "#{flag} #{ISO3166::Country[code]&.common_name || code}"
  end

  # Columns that sort A-Z on the first click. Everything else sorts biggest or newest
  # first, since that's the question being asked.
  ASCENDING_FIRST = %w[title].freeze

  def default_sort_direction(column)
    ASCENDING_FIRST.include?(column) ? "asc" : "desc"
  end

  # A per-event column header that sorts the table by that column: in place via the
  # table-sort controller, or by reloading with ?sort= without JavaScript.
  def event_sort_link(label, column)
    current = @sort == column
    direction =
      if current then @direction == "asc" ? "desc" : "asc"
      else default_sort_direction(column)
      end
    arrow = (@direction == "asc" ? " ▲" : " ▼") if current

    link_to "#{label}#{arrow}",
            internal_reports_path(start_date: @start_date.to_date, end_date: @end_date.to_date,
                                  **@filters, sort: column, direction: direction),
            class: "link-body-emphasis text-decoration-none",
            data: { table_sort_target: "link", action: "table-sort#sort",
                    table_sort_column_param: column, table_sort_label_param: label }
  end
end
