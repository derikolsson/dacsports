class Internal::EventsController < Internal::ApplicationController
  before_action :set_event, only: [ :edit, :update, :destroy, :go_live, :end_event, :mark_replay_pending, :mark_technical_difficulties, :publish_replay ]

  def index
    today_start = Time.current.beginning_of_day
    @events = Event.includes(event_teams: :team)
                   .where("start_at >= ?", today_start)
                   .order(:start_at)
  end

  def archive
    today_start = Time.current.beginning_of_day
    @events = Event.includes(event_teams: :team)
                   .where("start_at < ?", today_start)
                   .order(start_at: :desc)
  end

  def new
    @event = Event.new(
      time_zone: "America/Chicago",
      status: "upcoming",
      visible: true
    )
  end

  def create
    @event = Event.new(event_params)
    if @event.save
      redirect_to internal_events_path, notice: "Event created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @event.update(event_params)
      redirect_to internal_events_path, notice: "Event updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @event.destroy
    redirect_to internal_events_path, notice: "Event deleted successfully"
  end

  # State transitions
  def go_live
    if @event.go_live!
      redirect_to internal_events_path, notice: "Event is now live!"
    else
      redirect_to internal_events_path, alert: "Could not go live. Check that live embed code is present."
    end
  end

  def end_event
    if @event.end_event!
      redirect_to internal_events_path, notice: "Event has ended"
    else
      redirect_to internal_events_path, alert: "Could not end event"
    end
  end

  def mark_replay_pending
    if @event.mark_replay_pending!
      redirect_to internal_events_path, notice: "Event marked as replay pending"
    else
      redirect_to internal_events_path, alert: "Could not mark replay pending"
    end
  end

  def mark_technical_difficulties
    if @event.mark_technical_difficulties!
      redirect_to internal_events_path, notice: "Event marked as technical difficulties"
    else
      redirect_to internal_events_path, alert: "Could not mark technical difficulties"
    end
  end

  def publish_replay
    if @event.publish_replay!
      redirect_to internal_events_path, notice: "Replay is now available!"
    else
      redirect_to internal_events_path, alert: "Could not publish replay. Check that replay embed code is present."
    end
  end

  # Mints (or finds) the signed playback ID for the pasted asset, so the operator never
  # has to go dig one out of the Mux dashboard.
  def resolve_signed_playback
    @event = Event.find(params[:id])

    if @event.mux_asset_id.blank?
      redirect_to edit_internal_event_path(@event), alert: "Enter and save a Mux Asset ID first."
      return
    end

    signed_id = MuxSignedPlaybackId.for_asset(@event.mux_asset_id)
    @event.update!(mux_replay_signed_playback_id: signed_id)
    redirect_to edit_internal_event_path(@event), notice: "Signed playback ID resolved: #{signed_id}"
  rescue MuxSignedPlaybackId::Error, ActiveRecord::RecordInvalid => e
    redirect_to edit_internal_event_path(@event), alert: "Could not resolve signed playback ID: #{e.message}"
  end

  private

  def set_event
    @event = Event.find(params[:id])
  end

  def event_params
    params.require(:event).permit(
      :title, :slug, :start_at, :stream_starts_at, :time_zone,
      :mux_live_playback_id, :mux_replay_playback_id,
      :mux_live_signed_playback_id, :mux_replay_signed_playback_id, :mux_asset_id,
      :replay_start_time, :replay_end_time,
      :live_embed_code, :replay_embed_code, :status, :visible,
      :short_name, :description, :sport, :location, :round,
      event_teams_attributes: [ :id, :team_id, :_destroy ]
    )
  end
end
