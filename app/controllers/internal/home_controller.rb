class Internal::HomeController < Internal::ApplicationController
  def index
    query = DashboardQuery.new

    @active_viewers = Rails.cache.fetch("active_viewers", expires_in: 10.seconds) { query.active_viewers }
    @active_viewers_by_event = Rails.cache.fetch("dashboard/active_viewers_by_event", expires_in: 10.seconds) do
      query.active_viewers_by_event
    end
    @total_views = Rails.cache.fetch("total_views", expires_in: 10.seconds) { query.view_counts }
    @browser_breakdown = Rails.cache.fetch("browser_breakdown", expires_in: 10.seconds) { query.browser_breakdown }
    @os_breakdown = Rails.cache.fetch("os_breakdown", expires_in: 10.seconds) { query.os_breakdown }
    @device_breakdown = Rails.cache.fetch("device_breakdown", expires_in: 10.seconds) { query.device_breakdown }
  end
end
