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
end
