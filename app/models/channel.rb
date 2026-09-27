# A Mux live stream the venue encoders push to. Events pick the channel they air on, so
# the stream's playback IDs live here once rather than being pasted onto every event.
class Channel < ApplicationRecord
  PUBLIC = MuxRuby::PlaybackPolicy::PUBLIC

  class SyncError < StandardError; end

  has_many :events, dependent: :restrict_with_error

  normalizes :mux_live_stream_id, with: ->(id) { id.strip.presence }

  validates :name, presence: true
  validates :mux_live_stream_id, uniqueness: true, allow_nil: true

  scope :alphabetical, -> { order(:name) }

  # Pulls the public playback ID off the Mux stream and finds (or mints) the signed one.
  def sync_from_mux!
    raise SyncError, "Set the Mux live stream ID first" if mux_live_stream_id.blank?

    stream = MuxRuby::LiveStreamsApi.new.get_live_stream(mux_live_stream_id).data
    self.mux_live_playback_id = Array(stream.playback_ids).find { |p| p.policy.to_s == PUBLIC }&.id
    self.mux_live_signed_playback_id = MuxSignedPlaybackId.for_live_stream(mux_live_stream_id)
    save!
  rescue MuxRuby::ApiError => e
    raise SyncError, "Mux live stream #{mux_live_stream_id}: #{e.message}"
  rescue MuxSignedPlaybackId::Error => e
    raise SyncError, e.message
  end
end
