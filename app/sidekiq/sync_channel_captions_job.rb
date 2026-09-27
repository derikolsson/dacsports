class SyncChannelCaptionsJob
  include Sidekiq::Job

  # The error is already on the channel for the admin page. Only a live stream is worth
  # retrying; Sidekiq's backoff keeps trying until it goes idle.
  def perform(channel_id)
    Channel.find_by(id: channel_id)&.sync_captions_to_mux!
  rescue Channel::StreamActive
    raise
  rescue Channel::SyncError
    nil
  end
end
