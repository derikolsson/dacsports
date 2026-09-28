require "csv"

# The viewership report as a spreadsheet: a header block saying exactly what was
# counted, the summary, then one row per event.
class ReportsCsv
  def initialize(query, audience:, summary:, event_stats:, team: nil)
    @query = query
    @audience = audience
    @team = team
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
      csv << [ "Sport", @query.sport ] if @query.sport
      csv << [ "Team", @team ] if @team
      csv << []
      csv << [ "", "Users", "Views" ]
      csv << [ "Live", @summary[:live][:users], @summary[:live][:views] ]
      csv << [ "VOD", @summary[:vod][:users], @summary[:vod][:views] ]
      csv << [ "Est. hours with player open", (@summary[:player][:minutes] / 60.0).round ]
      csv << []
      csv << event_header
      @event_stats.each { |row| csv << event_row(row) }
    end
  end

  private

  def event_header
    [ "Event", "Aired (Central)", "Sport", "Peak live (at once)", "Est. hours with player open" ] +
      @query.event_columns.values.flat_map { |label| [ "#{label} viewers", "#{label} views" ] }
  end

  def event_row(row)
    [ row["title"], row["start_at"]&.in_time_zone("America/Chicago")&.strftime("%Y-%m-%d %H:%M"), row["sport"], row["live_peak"].to_i, (row["player_minutes"].to_f / 60).round(1) ] +
      @query.event_columns.keys.flat_map { |key| [ row["#{key}_viewers"].to_i, row["#{key}_views"].to_i ] }
  end
end
