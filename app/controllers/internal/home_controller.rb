class Internal::HomeController < Internal::ApplicationController
  def index
    @active_viewers = Rails.cache.fetch("active_viewers", expires_in: 10.seconds) do
      EventVisit.where("last_seen_at > ?", 3.minutes.ago).distinct.count(:session_id)
    end

    @active_viewers_by_event = Rails.cache.fetch("active_viewers_by_event", expires_in: 10.seconds) do
      EventVisit.where("last_seen_at > ?", 3.minutes.ago)
               .group(:event_id, :event_status)
               .distinct
               .count(:session_id)
    end

    @total_views = Rails.cache.fetch("total_views", expires_in: 10.seconds) do
      {
        all_time: EventVisit.count,
        last_24h: EventVisit.where("started_at > ?", 24.hours.ago).count,
        last_7d: EventVisit.where("started_at > ?", 7.days.ago).count
      }
    end

    # Only show device analytics for sessions that have actually watched events
    # Use joins instead of WHERE IN to avoid query size issues with large datasets
    @browser_breakdown = Rails.cache.fetch("browser_breakdown", expires_in: 10.seconds) do
      Session.joins(:event_visits)
             .distinct
             .group(:browser_name)
             .count
             .sort_by { |_k, v| -v }
             .first(10)
    end

    @os_breakdown = Rails.cache.fetch("os_breakdown", expires_in: 10.seconds) do
      Session.joins(:event_visits)
             .distinct
             .group(:os_name)
             .count
             .sort_by { |_k, v| -v }
             .first(10)
    end

    @device_breakdown = Rails.cache.fetch("device_breakdown", expires_in: 10.seconds) do
      Session.joins(:event_visits)
             .distinct
             .group(:device_type)
             .count
             .sort_by { |_k, v| -v }
    end
  end
end
