class Event < ApplicationRecord
  # Associations
  belongs_to :channel, optional: true
  has_many :event_visits, dependent: :destroy
  has_many :event_slugs, dependent: :destroy
  has_many :event_teams, dependent: :destroy
  has_many :teams, through: :event_teams
  accepts_nested_attributes_for :event_teams, allow_destroy: true, reject_if: proc { |attrs| attrs["team_id"].blank? }

  # The live stream's playback IDs come from the channel the event airs on.
  delegate :mux_live_playback_id, :mux_live_signed_playback_id, to: :channel, allow_nil: true

  # A new poster image from the internal form, and its "remove" box. The image itself
  # lives in S3 (see EventPoster); only its key is stored here.
  attr_accessor :poster, :remove_poster

  # Available sports
  SPORTS = [
    "Men's Soccer",
    "Women's Soccer",
    "Men's Volleyball",
    "Women's Volleyball",
    "Men's Basketball",
    "Women's Basketball",
    "Men's Football",
    "Women's Football",
    "Baseball"
  ].freeze

  # Enum for status
  enum :status, {
    upcoming: "upcoming",
    live: "live",
    ended: "ended",
    replay_pending: "replay_pending",
    replay_available: "replay_available",
    technical_difficulties: "technical_difficulties"
  }, default: :upcoming

  # Validations
  validates :title, :start_at, :time_zone, presence: true
  validate :live_video_source_present, if: -> { live? }
  validate :replay_video_source_present, if: -> { replay_available? }
  validates :sport, inclusion: { in: SPORTS, allow_blank: true }
  validates :slug, presence: true, uniqueness: true
  validate :poster_is_a_supported_image, if: -> { poster.present? }

  # A stream may still be up in technical difficulties; after these it's over.
  STREAMING_STATUSES = %w[live technical_difficulties].freeze
  ENDED_STATUSES = %w[ended replay_pending replay_available].freeze

  # Scopes
  scope :visible, -> { where(visible: true) }
  scope :upcoming_events, -> { upcoming.where("start_at >= ?", Time.current.beginning_of_day) }
  scope :past, -> { where(status: ENDED_STATUSES) }
  scope :by_date, -> { order(start_at: :desc) }

  # Events that would actually render a player at /embed/:slug right now — the state has
  # to be playable AND the matching signed playback ID has to exist. Anything else shows
  # a slate and signs no token.
  scope :embeddable, -> {
    visible.left_joins(:channel).where(
      "(events.status = 'live' AND channels.mux_live_signed_playback_id IS NOT NULL AND channels.mux_live_signed_playback_id <> '') OR " \
      "(events.status = 'replay_available' AND events.mux_replay_signed_playback_id IS NOT NULL AND events.mux_replay_signed_playback_id <> '')"
    )
  }

  # Events whose live stream can be previewed through the embed before it is live. The
  # stream is still ahead of these states; once an event has ended there is nothing on
  # the live playback ID to look at.
  LIVE_PREVIEWABLE_STATUSES = %w[upcoming technical_difficulties].freeze
  scope :live_previewable, -> {
    joins(:channel)
      .where(status: LIVE_PREVIEWABLE_STATUSES)
      .where("channels.mux_live_signed_playback_id IS NOT NULL AND channels.mux_live_signed_playback_id <> ''")
      .order(:start_at)
  }

  # The slug this event would get if its slug were cleared, e.g.
  # 2026-womens-volleyball-game-of-the-week-oct-05--north-lake-cedar-valley. Taken from
  # the year, sport, round, date and teams (title when there are none), with -2, -3, …
  # added when another event already holds it, now or in its history.
  def suggested_slug
    local_start = start_at&.in_time_zone(time_zone)
    teams = event_teams.reject(&:marked_for_destruction?).filter_map(&:team)
    matchup = teams.any? ? teams.map(&:slug).join("-") : title.to_s.parameterize
    lead = [
      local_start&.strftime("%Y"),
      sport.to_s.delete("'").parameterize,
      round.to_s.parameterize,
      local_start&.strftime("%b-%d")&.downcase
    ].compact_blank.join("-")
    base = [ lead, matchup ].compact_blank.join("--")

    candidate, n = base, 1
    candidate = "#{base}-#{n += 1}" while slug_taken_elsewhere?(candidate)
    candidate
  end

  # Shown by the players before playback starts, in place of Mux's own thumbnail.
  def poster_url
    EventPoster.url(poster_key)
  end

  # Helper method for date display
  def event_date
    start_at&.in_time_zone(time_zone)&.to_date
  end

  # When viewers should expect the stream, in the event's zone. The stream usually opens
  # ahead of the game, so this is the stream start when one is set and the game time
  # otherwise.
  def stream_begins_at
    (stream_starts_at || start_at)&.in_time_zone(time_zone)
  end

  # Sport emoji helper
  def sport_emoji
    return "" if sport.blank?

    sport_lower = sport.downcase

    if sport_lower.include?("soccer")
      "⚽"
    elsif sport_lower.include?("volleyball")
      "🏐"
    elsif sport_lower.include?("basketball")
      "🏀"
    elsif sport_lower.include?("football")
      "🏈"
    elsif sport_lower.include?("baseball")
      "⚾"
    else
      ""
    end
  end

  # True when /embed/:slug will serve a signed player for this event.
  def embeddable?
    (live? && mux_live_signed_playback_id.present?) ||
      (replay_available? && mux_replay_signed_playback_id.present?)
  end

  # True when the live stream can be checked through the embed ahead of going live:
  # the signed live ID is in place but the state still shows partners a slate.
  def live_previewable?
    LIVE_PREVIEWABLE_STATUSES.include?(status) && mux_live_signed_playback_id.present?
  end

  # Recordings arrive public-only (see MuxSignedPlaybackId#recordings_signed?), so each
  # replay's signed ID has to be minted from its asset before the embed can play it. A new
  # asset needs its own, even when an old one is still on file. The site plays the public
  # ID, which comes from the same asset, so a missing one is filled in the same pass.
  def needs_signed_replay?
    mux_asset_id.present? &&
      (mux_replay_signed_playback_id.blank? || mux_replay_playback_id.blank? || saved_change_to_mux_asset_id?)
  end

  def resolve_signed_replay!
    ids = MuxSignedPlaybackId.for_asset(mux_asset_id)
    update!(mux_replay_signed_playback_id: ids.signed_id,
            mux_replay_playback_id: ids.public_id || mux_replay_playback_id)
  end

  def can_go_live?
    upcoming? && has_live_video_source?
  end

  def can_end?
    live? || technical_difficulties?
  end

  def can_mark_replay_pending?
    live? || technical_difficulties?
  end

  def can_mark_technical_difficulties?
    live?
  end

  # The site can't play a signed ID, so publishing waits for something it can.
  def can_publish_replay?
    (replay_pending? || technical_difficulties?) && has_site_replay_source?
  end

  # State transitions
  def go_live!
    return false unless can_go_live?
    update!(status: :live)
  end

  def end_event!
    return false unless can_end?
    update!(status: :ended)
  end

  def mark_replay_pending!
    return false unless can_mark_replay_pending?
    update!(status: :replay_pending)
  end

  def mark_technical_difficulties!
    return false unless can_mark_technical_difficulties?
    update!(status: :technical_difficulties)
  end

  def publish_replay!
    return false unless can_publish_replay?
    update!(status: :replay_available)
  end

  # Related events - same sport within +/- 3 days
  def related_events
    return Event.none if sport.blank? || start_at.blank?

    Event.visible
         .where(sport: sport)
         .where.not(id: id)
         .where("start_at BETWEEN ? AND ?",
                start_at - 3.days,
                start_at + 3.days)
         .order(:start_at)
  end

  # Cache busting
  before_save :bump_force_reload_count

  # Slug history tracking. A blank slug is generated, on create or after it's cleared.
  before_validation :generate_slug, if: -> { slug.blank? }
  before_update :archive_slug_if_changed

  # Posters go up before the row is saved, so a failed upload fails the save; the old
  # image only comes down once the new key is committed.
  before_save :store_poster
  after_update_commit :delete_replaced_poster, if: :saved_change_to_poster_key?
  after_destroy_commit -> { delete_poster(poster_key) }

  # Pull Mux Data an hour after a show ends, once most of its views have closed.
  after_commit :import_mux_data_later, if: :just_ended?

  private

  def poster_is_a_supported_image
    unless EventPoster::CONTENT_TYPES.key?(poster.content_type)
      errors.add(:poster, "must be a JPEG, PNG or WebP image")
    end
    if poster.size > EventPoster::MAX_BYTES
      errors.add(:poster, "must be smaller than #{EventPoster::MAX_BYTES / 1.megabyte} MB")
    end
  end

  def store_poster
    if poster.present?
      self.poster_key = EventPoster.upload(poster.to_io, content_type: poster.content_type)
    elsif ActiveModel::Type::Boolean.new.cast(remove_poster)
      self.poster_key = nil
    end
  rescue EventPoster::Error => e
    errors.add(:poster, "could not be uploaded: #{e.message}")
    throw :abort
  end

  def delete_replaced_poster
    delete_poster(poster_key_before_last_save)
  end

  # A leftover object only costs storage, so a failed delete shouldn't fail the request.
  def delete_poster(key)
    EventPoster.delete(key) if key.present?
  rescue EventPoster::Error => e
    Rails.logger.warn("Could not delete poster #{key}: #{e.message}")
  end

  def just_ended?
    was, now = saved_change_to_status
    STREAMING_STATUSES.include?(was) && ENDED_STATUSES.include?(now)
  end

  def import_mux_data_later
    MuxDataImportJob.perform_in(1.hour)
  end

  def bump_force_reload_count
    if title_changed? || replay_embed_code_changed? ||
       channel_id_changed? || mux_replay_playback_id_changed? ||
       mux_replay_signed_playback_id_changed? ||
       status_changed?
      self.force_reload_count += 1
    end
  end

  def has_live_video_source?
    mux_live_playback_id.present? || mux_live_signed_playback_id.present?
  end

  def has_site_replay_source?
    replay_embed_code.present? || mux_replay_playback_id.present?
  end

  def has_replay_video_source?
    replay_embed_code.present? || mux_replay_playback_id.present? || mux_replay_signed_playback_id.present?
  end

  def live_video_source_present
    unless has_live_video_source?
      errors.add(:base, "Live video source required (pick a channel)")
    end
  end

  def replay_video_source_present
    unless has_replay_video_source?
      errors.add(:base, "Replay video source required (embed code or Mux playback ID)")
    end
  end

  def generate_slug
    self.slug = suggested_slug
  end

  def slug_taken_elsewhere?(candidate)
    Event.where(slug: candidate).where.not(id: id).exists? ||
      EventSlug.where(slug: candidate).where.not(event_id: id).exists?
  end

  def archive_slug_if_changed
    if slug_changed?
      event_slugs.find_or_create_by(slug: slug_was)
    end
  end
end
