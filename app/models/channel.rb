# A Mux live stream the venue encoders push to. Events pick the channel they air on, so
# the stream's playback IDs live here once rather than being pasted onto every event. The
# name is the stream's title in Mux, so it reads the same in both places.
class Channel < ApplicationRecord
  PUBLIC = MuxRuby::PlaybackPolicy::PUBLIC

  class SyncError < StandardError; end
  # Worth retrying: Mux takes caption changes once the stream goes idle.
  class StreamActive < SyncError; end

  has_many :events, dependent: :restrict_with_error
  has_one :vocabulary, dependent: :destroy
  accepts_nested_attributes_for :vocabulary, reject_if: ->(attrs) { attrs["id"].blank? && attrs["phrases"].blank? }

  normalizes :mux_live_stream_id, with: ->(id) { id.strip.presence }

  before_validation { self.name = mux_live_stream_id if name.blank? }

  validates :name, presence: true
  validates :mux_live_stream_id, presence: true, uniqueness: true

  scope :alphabetical, -> { order(:name) }

  after_commit :sync_captions_later, if: -> { saved_change_to_captions_enabled? }

  # Pulls the title and public playback ID off the Mux stream and finds (or mints) the
  # signed one.
  def sync_from_mux!
    raise SyncError, "Set the Mux live stream ID first" if mux_live_stream_id.blank?

    stream = MuxRuby::LiveStreamsApi.new.get_live_stream(mux_live_stream_id).data
    self.name = stream.meta&.title.presence || name
    self.mux_live_playback_id = Array(stream.playback_ids).find { |p| p.policy.to_s == PUBLIC }&.id
    self.mux_live_signed_playback_id = MuxSignedPlaybackId.for_live_stream(mux_live_stream_id)
    save!
  rescue MuxRuby::ApiError => e
    raise SyncError, "Mux live stream #{mux_live_stream_id}: #{e.message}"
  rescue MuxSignedPlaybackId::Error => e
    raise SyncError, e.message
  end

  def sync_captions_later
    SyncChannelCaptionsJob.perform_async(id)
  end

  # Points the stream's generated captions at the shared and channel vocabularies, or
  # turns them off. Mux only takes this while the stream is idle.
  def sync_captions_to_mux!
    raise SyncError, "Set the Mux live stream ID first" if mux_live_stream_id.blank?

    api = MuxRuby::LiveStreamsApi.new
    stream = api.get_live_stream(mux_live_stream_id).data
    if captions_enabled? && stream.latency_mode.to_s == "low"
      raise SyncError, "Mux can't caption a low-latency stream; switch it to standard or reduced latency"
    end
    raise StreamActive, "The stream is live; captions will update once it's idle" if stream.status.to_s == "active"

    request = MuxRuby::UpdateLiveStreamGeneratedSubtitlesRequest.new(
      generated_subtitles: captions_enabled? ? [ generated_subtitle_settings ] : []
    )
    api.update_live_stream_generated_subtitles(mux_live_stream_id, request)
    update!(captions_synced_at: Time.current, captions_sync_error: nil)
  rescue MuxRuby::ApiError, SyncError, Vocabulary::SyncError => e
    update_columns(captions_sync_error: e.message.truncate(255))
    raise e.is_a?(SyncError) ? e : SyncError.new("Mux live stream #{mux_live_stream_id}: #{e.message}")
  end

  private

  # The shared list goes first: past Mux's 1,000-phrase cap, later phrases are dropped.
  def generated_subtitle_settings
    vocabularies = [ Vocabulary.global, vocabulary ].compact.select { |v| v.all_phrases.any? }
    vocabularies.each { |v| v.sync_to_mux! if v.mux_vocabulary_id.blank? }

    MuxRuby::LiveStreamGeneratedSubtitleSettings.new(
      name: "English (auto)",
      language_code: "en",
      passthrough: "channel:#{id}",
      transcription_vocabulary_ids: vocabularies.map(&:mux_vocabulary_id)
    )
  end
end
