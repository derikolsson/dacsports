require "csv"

# The viewership report as a spreadsheet: a header block saying exactly what was
# counted, the summary, then one row per event.
class ReportsCsv
  def initialize(query, audience:, summary:, event_stats:)
    @query = query
    @audience = audience
    @summary = summary
    @event_stats = event_stats
  end

  def filename
    audience = @audience.parameterize.presence || "audience"
    "dsn-viewership-#{@query.start_date.to_date}-to-#{@query.end_date.to_date}-#{@query.basis}-#{audience}.csv"
  end

  def to_csv
    CSV.generate do |csv|
      csv << [ "DAC Sports Network viewership" ]
      csv << [ "Period", "#{@query.start_date.to_date} to #{@query.end_date.to_date}" ]
      csv << [ "Counting", @query.activity? ? "Viewing that happened in the period" : "All viewing of events that aired in the period" ]
      csv << [ "Audience", @audience ]
      csv << []
      csv << [ "", "Users", "Views" ]
      csv << [ "Live", @summary[:live][:users], @summary[:live][:views] ]
      csv << [ "VOD", @summary[:vod][:users], @summary[:vod][:views] ]
      csv << []
      csv << event_header
      @event_stats.each { |row| csv << event_row(row) }
    end
  end

  private

  def event_header
    [ "Event", "Aired (Central)", "Sport" ] +
      @query.event_columns.values.flat_map { |label| [ "#{label} viewers", "#{label} views" ] }
  end

  def event_row(row)
    [ row["title"], row["start_at"]&.in_time_zone("America/Chicago")&.strftime("%Y-%m-%d %H:%M"), row["sport"] ] +
      @query.event_columns.keys.flat_map { |key| [ row["#{key}_viewers"].to_i, row["#{key}_views"].to_i ] }
  end
end
