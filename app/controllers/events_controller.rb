class EventsController < ApplicationController
  skip_forgery_protection only: :status

  def index
    @live_events = Event.visible.live.order(start_at: :asc)
    @upcoming_events = Event.visible.upcoming.where("start_at >= ?", Date.current).order(start_at: :asc)
    @past_events = Event.visible.where(status: [ :ended, :replay_pending, :replay_available ]).order(start_at: :desc)
  end

  def show
    @event = Event.find_by!(slug: params[:slug])
    @title = case @event.status
    when "live" then "Live: #{@event.title}"
    when "replay_available" then "Replay: #{@event.title}"
    else @event.title
    end

    render layout: "watch"
  end

  def status
    # Track visit
    if params[:enabled] == "true" && params[:session_id].present?
      EventVisitJob.perform_async(
        params[:session_id],
        params[:event_id],
        params[:event_status],
        params[:started_at],
        Time.now.utc.iso8601(6)
      )
    end

    # Return cached status
    status = Rails.cache.fetch("event_status/#{params[:slug]}", expires_in: 30.seconds) do
      event = Event.find_by(slug: params[:slug])
      return head 404 unless event

      {
        status: event.status,
        force_reload_version: event.force_reload_count,
        ttl: Dacsports.redis.get("event_status_ttl").to_i
      }
    end

    render json: status
  end
end
