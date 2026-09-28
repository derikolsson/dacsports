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

  # A per-event column header that sorts the table by that column. Numbers sort biggest
  # first on the first click, since that's the question being asked.
  def event_sort_link(label, column)
    current = @sort == column
    direction =
      if current then @direction == "asc" ? "desc" : "asc"
      else %w[title start_at].include?(column) ? "asc" : "desc"
      end
    arrow = (@direction == "asc" ? " ▲" : " ▼") if current

    link_to "#{label}#{arrow}",
            internal_reports_path(start_date: @start_date.to_date, end_date: @end_date.to_date,
                                  **@filters, sort: column, direction: direction),
            class: "link-body-emphasis text-decoration-none"
  end
end
