class Internal::HomeController < Internal::ApplicationController
  def index
    query = DashboardQuery.new(source: params[:source])
    @source = query.source
    cache_key = "dashboard/v2/#{@source}"

    # Right-now figures cover every audience, so they share a key across the selector.
    @active_viewers = Rails.cache.fetch("dashboard/v2/active_viewers", expires_in: 10.seconds) { query.active_viewers }
    @active_viewers_by_event = Rails.cache.fetch("dashboard/v2/active_viewers_by_event", expires_in: 10.seconds) do
      query.active_viewers_by_event
    end

    # Week-long figures barely move minute to minute.
    @week = Rails.cache.fetch("#{cache_key}/week", expires_in: 1.minute) { query.week }
    @partner_share = Rails.cache.fetch("dashboard/v2/partner_share", expires_in: 1.minute) { query.partner_share }
    @week_link = internal_reports_path(**query.week_range, source: @source)
    @trend = Rails.cache.fetch("#{cache_key}/trend", expires_in: 5.minutes) do
      ReportsQuery.new(start_date: 29.days.ago.to_date, end_date: Date.current, source: @source).daily_series
    end
    @peak_today = Rails.cache.fetch("#{cache_key}/peak_today", expires_in: 1.minute) { query.peak_today }
    @top_events = Rails.cache.fetch("#{cache_key}/top_events", expires_in: 5.minutes) { query.top_events }
    @top_partners = Rails.cache.fetch("dashboard/v2/top_partners", expires_in: 5.minutes) { query.top_partners }
    @device_share = Rails.cache.fetch("#{cache_key}/device_share", expires_in: 5.minutes) { query.device_share }
    @upcoming_events = query.upcoming_events
  end
end
