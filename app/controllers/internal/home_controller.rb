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

    @counts = Rails.cache.fetch("#{cache_key}/counts", expires_in: 10.seconds) { query.audience_counts }
    @browser_breakdown = Rails.cache.fetch("#{cache_key}/browsers", expires_in: 10.seconds) { query.browser_breakdown }
    @os_breakdown = Rails.cache.fetch("#{cache_key}/os", expires_in: 10.seconds) { query.os_breakdown }
    @device_breakdown = Rails.cache.fetch("#{cache_key}/devices", expires_in: 10.seconds) { query.device_breakdown }
  end
end
