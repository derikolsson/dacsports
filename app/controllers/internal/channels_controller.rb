class Internal::ChannelsController < Internal::ApplicationController
  before_action :require_admin
  before_action :set_channel, only: [ :edit, :update, :destroy ]

  def index
    @channels = Channel.alphabetical.includes(:events)
  end

  def new
    @channel = Channel.new
    @channel.build_vocabulary
  end

  def create
    @channel = Channel.new(channel_params)
    if @channel.save
      sync_and_redirect("Channel created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @channel.vocabulary || @channel.build_vocabulary
  end

  def update
    if @channel.update(channel_params)
      sync_and_redirect("Channel updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @channel.destroy
      redirect_to internal_channels_path, notice: "Channel deleted"
    else
      redirect_to internal_channels_path, alert: "Cannot delete a channel with events on it"
    end
  end

  private

  def set_channel
    @channel = Channel.find(params[:id])
  end

  def channel_params
    params.require(:channel).permit(:mux_live_stream_id, :captions_enabled, vocabulary_attributes: [ :id, :phrases ])
  end

  # Refreshes the playback IDs from Mux on every save so they can't drift from the stream.
  def sync_and_redirect(notice)
    return redirect_to(internal_channels_path, notice: notice) if @channel.mux_live_stream_id.blank?

    @channel.sync_from_mux!
    redirect_to internal_channels_path, notice: "#{notice} and synced from Mux"
  rescue Channel::SyncError => e
    redirect_to edit_internal_channel_path(@channel), alert: "#{notice}, but the Mux sync failed: #{e.message}"
  end
end
