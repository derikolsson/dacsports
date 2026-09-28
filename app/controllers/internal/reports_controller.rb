class Internal::ReportsController < Internal::ApplicationController
  def index
    parse_date_range
    @partner_options = ReportsQuery.partner_sources
    parse_source
    @basis = ReportsQuery::BASES.include?(params[:basis]) ? params[:basis] : ReportsQuery::ACTIVITY
    @teams = Team.order(:name)
    @sport = params[:sport] if Event::SPORTS.include?(params[:sport])
    @team = @teams.find_by(id: params[:team_id]) if params[:team_id].present?

    # Everything but the dates, for links that change only the period.
    @filters = { source: @source, basis: @basis, sport: @sport, team_id: @team&.id }.compact

    @query = ReportsQuery.new(start_date: @start_date, end_date: @end_date, **@filters)

    # Every filter is part of the cache key, or changing one would serve the previous
    # selection's numbers. Versioned because the cached hashes changed shape.
    cache_key = "reports/v7/#{@start_date.to_date}/#{@end_date.to_date}/#{@filters.to_query}"

    @summary = Rails.cache.fetch("#{cache_key}/summary", expires_in: 10.minutes) do
      @query.summary_stats
    end

    @previous_summary = Rails.cache.fetch("#{cache_key}/previous_summary", expires_in: 10.minutes) do
      @query.previous_period&.summary_stats
    end

    @trend = Rails.cache.fetch("#{cache_key}/trend", expires_in: 10.minutes) do
      @query.daily_series
    end

    @device_breakdown = Rails.cache.fetch("#{cache_key}/devices", expires_in: 10.minutes) do
      @query.device_breakdown
    end

    @os_breakdown = Rails.cache.fetch("#{cache_key}/os", expires_in: 10.minutes) do
      @query.os_breakdown
    end

    @event_stats = Rails.cache.fetch("#{cache_key}/events", expires_in: 10.minutes) do
      @query.per_event_stats
    end

    if @query.all_partners?
      @partner_stats = Rails.cache.fetch("#{cache_key}/partners", expires_in: 10.minutes) do
        @query.per_partner_stats
      end
    end

    sort_event_stats

    respond_to do |format|
      format.html
      format.csv do
        csv = ReportsCsv.new(@query, audience: audience_label, team: @team&.name,
                                     summary: @summary, event_stats: @event_stats)
        send_data csv.to_csv, filename: csv.filename, type: "text/csv"
      end
    end
  end

  private

  # Only an audience we actually know about, so the value cannot be used to probe.
  def parse_source
    requested = params[:source].to_s
    @source =
      if requested == ReportsQuery::ALL_PARTNERS || @partner_options.to_a.any? { |(_, v)| v == requested }
        requested
      else
        ReportsQuery::ON_SITE
      end
    @audience_label = audience_label
  end

  def audience_label
    case @source
    when ReportsQuery::ON_SITE then "dacsports.net"
    when ReportsQuery::ALL_PARTNERS then "All partner sites"
    else @partner_options.to_a.find { |(_, v)| v == @source }&.first || @source
    end
  end

  # Sorted in Ruby: the rows are cached, one per event, and few enough that re-querying
  # per column would only cost cache hits. Only columns the table shows are allowed.
  def sort_event_stats
    sortable = [ "start_at", "title", "live_peak", "player_minutes" ] +
      @query.event_columns.keys.flat_map { |key| [ "#{key}_viewers", "#{key}_views" ] }
    @sort = sortable.include?(params[:sort]) ? params[:sort] : "start_at"
    @direction = params[:direction] == "desc" ? "desc" : "asc"

    @event_stats = @event_stats.sort_by do |row|
      value = row[@sort]
      @sort == "title" ? value.to_s.downcase : (value || 0)
    end
    @event_stats.reverse! if @direction == "desc"
  end

  def parse_date_range
    @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current
    @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : @end_date - 30.days
  rescue ArgumentError
    @end_date = Date.current
    @start_date = @end_date - 30.days
  end
end
