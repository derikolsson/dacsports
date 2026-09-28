class Internal::ReportsController < Internal::ApplicationController
  def index
    parse_date_range
    @partner_options = ReportsQuery.partner_sources
    parse_source
    @basis = ReportsQuery::BASES.include?(params[:basis]) ? params[:basis] : ReportsQuery::ACTIVITY

    # Source and basis are part of the cache key, or switching either would serve the
    # previous selection's numbers. Versioned because the cached hashes changed shape.
    cache_key = "reports/v3/#{@start_date.to_date}/#{@end_date.to_date}/#{@source}/#{@basis}"

    @summary = Rails.cache.fetch("#{cache_key}/summary", expires_in: 10.minutes) do
      query.summary_stats
    end

    @device_breakdown = Rails.cache.fetch("#{cache_key}/devices", expires_in: 10.minutes) do
      query.device_breakdown
    end

    @os_breakdown = Rails.cache.fetch("#{cache_key}/os", expires_in: 10.minutes) do
      query.os_breakdown
    end

    @event_stats = Rails.cache.fetch("#{cache_key}/events", expires_in: 10.minutes) do
      query.per_event_stats
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
  end

  def parse_date_range
    @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current
    @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : @end_date - 30.days
  rescue ArgumentError
    @end_date = Date.current
    @start_date = @end_date - 30.days
  end

  def query
    @query ||= ReportsQuery.new(start_date: @start_date, end_date: @end_date, source: @source, basis: @basis)
  end
end
