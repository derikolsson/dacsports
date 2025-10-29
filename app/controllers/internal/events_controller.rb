class Internal::EventsController < Internal::ApplicationController
  before_action :set_event, only: [ :edit, :update, :destroy, :go_live, :end_event, :mark_replay_pending, :publish_replay ]

  def index
    @events = Event.order(start_at: :desc)
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

  def publish_replay
    if @event.publish_replay!
      redirect_to internal_events_path, notice: "Replay is now available!"
    else
      redirect_to internal_events_path, alert: "Could not publish replay. Check that replay embed code is present."
    end
  end

  private

  def set_event
    @event = Event.friendly.find(params[:id])
  end

  def event_params
    params.require(:event).permit(
      :title, :start_at, :time_zone,
      :live_embed_code, :replay_embed_code, :status, :visible,
      :short_name, :description, :sport, :location, :round
    )
  end
end
