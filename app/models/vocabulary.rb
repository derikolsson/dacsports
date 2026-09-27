# Words and names the live caption engine should favor: a Mux transcription vocabulary.
# The global one (no channel) is attached to every captioned stream and also takes in the
# team names and mascots; a channel can add its own on top.
#
# Mux accepts phrase edits at any time, but a stream only picks them up the next time it
# goes live.
class Vocabulary < ApplicationRecord
  # Mux uses at most this many phrases across all of a stream's vocabularies.
  MAX_PHRASES = 1000

  class SyncError < StandardError; end

  belongs_to :channel, optional: true

  # A channel's list is built alongside a new channel, before either has an ID.
  validates :channel_id, uniqueness: true, unless: -> { channel&.new_record? }
  validate :within_phrase_limit

  after_commit :sync_later, if: -> { saved_change_to_phrases? }

  def self.global
    find_or_create_by!(channel_id: nil)
  end

  def global?
    channel.nil?
  end

  # The phrases an admin typed, one per line.
  def phrase_list
    phrases.to_s.lines.map(&:strip).reject(&:blank?).uniq
  end

  # Team names and mascots, kept current without anyone retyping them.
  def team_phrases
    return [] unless global?

    (Team.alphabetical.pluck(:name) + Team::TEAM_COLORS.values.filter_map { |colors| colors[:mascot] }).uniq
  end

  def all_phrases
    (phrase_list + team_phrases).uniq(&:downcase)
  end

  def sync_later
    SyncVocabularyJob.perform_async(id)
  end

  def sync_to_mux!
    if all_phrases.empty?
      # Emptied out: have the streams stop listing it rather than update it to nothing.
      captioned_channels.each(&:sync_captions_later) if mux_vocabulary_id.present?
      return
    end

    api = MuxRuby::TranscriptionVocabulariesApi.new
    if mux_vocabulary_id.present?
      api.update_transcription_vocabulary(mux_vocabulary_id, MuxRuby::UpdateTranscriptionVocabularyRequest.new(**mux_attributes))
    else
      created = api.create_transcription_vocabulary(MuxRuby::CreateTranscriptionVocabularyRequest.new(**mux_attributes)).data
      self.mux_vocabulary_id = created.id
    end
    update!(synced_at: Time.current, sync_error: nil)

    # A brand-new vocabulary only reaches a stream once the stream lists its ID.
    captioned_channels.each(&:sync_captions_later) if mux_vocabulary_id_previously_changed?
  rescue MuxRuby::ApiError => e
    update_columns(sync_error: e.message.truncate(255))
    raise SyncError, "Mux vocabulary for #{label}: #{e.message}"
  end

  def label
    global? ? "all channels" : channel.name
  end

  private

  def mux_attributes
    { name: "DAC Sports: #{label}", phrases: all_phrases, passthrough: "vocabulary:#{id}" }
  end

  def captioned_channels
    global? ? Channel.where(captions_enabled: true) : [ channel ].select(&:captions_enabled?)
  end

  # Past the cap Mux silently drops phrases, so refuse to save a list that would get cut.
  def within_phrase_limit
    total = all_phrases.size + (global? ? largest_channel_phrase_count : global_phrase_count)
    return if total <= MAX_PHRASES

    errors.add(:phrases, "come to #{total} with the #{global? ? 'largest channel list' : 'shared list'}; Mux uses at most #{MAX_PHRASES}")
  end

  def largest_channel_phrase_count
    Vocabulary.where.not(channel_id: nil).map { |v| v.phrase_list.size }.max.to_i
  end

  def global_phrase_count
    Vocabulary.find_by(channel_id: nil)&.all_phrases&.size.to_i
  end
end
