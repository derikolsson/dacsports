class Internal::ReportsController < Internal::ApplicationController
  def index
    parse_date_range

    cache_key = "reports/#{@start_date.to_date}/#{@end_date.to_date}"

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

  def parse_date_range
    @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current
    @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : @end_date - 30.days
  rescue ArgumentError
    @end_date = Date.current
    @start_date = @end_date - 30.days
  end

  def query
    @query ||= ReportsQuery.new(start_date: @start_date, end_date: @end_date)
  end
end
