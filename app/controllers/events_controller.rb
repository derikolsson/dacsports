class EventsController < ApplicationController
  skip_forgery_protection only: :status

  def index
    @events = Event.visible.order(start_at: :asc)
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
    if params[:enabled] == "true" && params[:visit_id].present? && params[:session_id].present?
      EventVisitJob.perform_async(
        params[:visit_id],
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
